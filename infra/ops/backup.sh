#!/usr/bin/env bash
# Nightly backup of everything that cannot be rebuilt from the repo:
#   1. the LibreChat database (users, conversations, messages)  -> mongodump archive
#   2. files users uploaded (images, uploads)                    -> tar.gz
# plus a manifest of document counts (used by restore.sh to prove a restore is complete)
# and SHA256 checksums. Everything goes to s3://<bucket>/backups/<UTC timestamp>/.
#
# The bucket is private, versioned and encrypted at rest (S3 default SSE-S3). A lifecycle rule
# deletes backups after 14 days. The last 3 days are also kept on the instance for fast restores.
#
# Run by cron every night (infra/cron/kape-lumen). By hand:  sudo /opt/kape/app/infra/ops/backup.sh
# Success/failure is published as the CloudWatch metric KapeLumen/BackupSuccess (alarm: kape-backup-missing),
# and a failure also emails kape-alerts straight away.
JOB=backup
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"
log_to_file

START=$(date +%s)
TS=$(date -u +%Y%m%dT%H%M%SZ)
BUCKET=$(env_get CONTENT_BUCKET)
DEST="$BACKUP_DIR/$TS"

fail() {
  trap - ERR
  log "FAILED: $*"
  rm -rf "$DEST"   # never leave a half-written backup that "latest" could pick up
  metric BackupSuccess 0 || true
  alert "Kape Lumen: backup FAILED" "Backup $TS failed on $(hostname): $*. Log: CloudWatch /kape/host, stream */automation." || true
  exit 1
}
trap 'fail "line $LINENO exited with status $?"' ERR

[ -n "$BUCKET" ] || fail "CONTENT_BUCKET is not set in $KAPE_ENV"
mkdir -p "$DEST"
log "starting backup $TS -> s3://$BUCKET/backups/$TS/"

# 1. Database. --archive streams to stdout, so no temporary files inside the container.
docker exec "$MONGO_CONTAINER" sh -c \
  'exec mongodump --quiet --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --db LibreChat --archive --gzip' \
  > "$DEST/mongo-LibreChat.archive.gz"
gzip -t "$DEST/mongo-LibreChat.archive.gz" || fail "database archive is not valid gzip"

# 2. Uploaded files (may be empty folders, which is fine).
tar -czf "$DEST/librechat-files.tar.gz" -C "$DATA_DIR/librechat" images uploads

# 3. Manifest: what the database held at backup time.
COUNTS=$(collection_counts "$DB_NAME")
[ -n "$COUNTS" ] || fail "could not read collection counts"
printf '{"timestamp":"%s","database":"%s","counts":%s}\n' "$TS" "$DB_NAME" "$COUNTS" > "$DEST/manifest.json"
( cd "$DEST" && sha256sum mongo-LibreChat.archive.gz librechat-files.tar.gz manifest.json > SHA256SUMS )
log "database counts: $COUNTS"

# 4. Off the instance: upload, then check every file arrived.
aws_ s3 cp --recursive --only-show-errors "$DEST/" "s3://$BUCKET/backups/$TS/"
if [ "$DRY_AWS" != 1 ]; then
  uploaded=$(aws_ s3 ls "s3://$BUCKET/backups/$TS/" | wc -l)
  [ "$uploaded" -eq 4 ] || fail "expected 4 files in S3, found $uploaded"
fi

# 5. Keep only the last 3 days locally (S3 keeps 14).
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name '20*Z' -mtime +2 -exec rm -rf {} +

SIZE=$(du -cb "$DEST"/* | tail -1 | cut -f1)
metric BackupSuccess 1
metric BackupSizeBytes "$SIZE" Bytes
log "backup $TS OK: $SIZE bytes in $(( $(date +%s) - START ))s"
