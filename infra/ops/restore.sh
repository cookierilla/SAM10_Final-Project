#!/usr/bin/env bash
# Restores a backup made by backup.sh.
#
#   restore.sh --test [TIMESTAMP|latest]        safe: restores into a SEPARATE database
#                                               (LibreChat_restoretest), checks every collection's
#                                               document count against the backup's manifest, then
#                                               deletes the test database. The live app is untouched.
#   restore.sh --live --yes [TIMESTAMP|latest]  disaster recovery: stops LibreChat, replaces the live
#                                               database and uploaded files, starts LibreChat again.
#
# Add --from-local to use the copy in /opt/kape/backups instead of downloading from S3
# (S3 is the default because it proves the off-instance copy works).
#
# Cron runs "--test latest" every week (infra/cron/kape-lumen). Results: metric
# KapeLumen/RestoreTestSuccess and the automation log (CloudWatch /kape/host).
JOB=restore
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"
log_to_file

MODE="" CONFIRM=0 FROM_LOCAL=0 TS=latest
for arg in "$@"; do
  case "$arg" in
    --test) MODE=test ;;
    --live) MODE=live ;;
    --yes) CONFIRM=1 ;;
    --from-local) FROM_LOCAL=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) TS=$arg ;;
  esac
done
[ -n "$MODE" ] || { echo "usage: restore.sh --test|--live --yes [TIMESTAMP|latest] [--from-local]" >&2; exit 2; }
[ "$MODE" = test ] || [ "$CONFIRM" = 1 ] || { echo "--live replaces the live database. Add --yes if you mean it." >&2; exit 2; }

START=$(date +%s)
BUCKET=$(env_get CONTENT_BUCKET)
TARGET_DB=$DB_NAME; [ "$MODE" = test ] && TARGET_DB=${DB_NAME}_restoretest

fail() {
  trap - ERR
  log "FAILED ($MODE): $*"
  [ "$MODE" = test ] && { metric RestoreTestSuccess 0 || true; mongo_eval "db.getSiblingDB('$TARGET_DB').dropDatabase()" >/dev/null 2>&1 || true; }
  [ "$MODE" = live ] && { docker start "$APP_CONTAINER" >/dev/null 2>&1 || true; }
  alert "Kape Lumen: restore $MODE FAILED" "Restore ($MODE) of backup $TS failed on $(hostname): $*" || true
  exit 1
}
trap 'fail "line $LINENO exited with status $?"' ERR

# 1. Find and fetch the backup.
if [ "$TS" = latest ]; then
  if [ "$FROM_LOCAL" = 1 ]; then
    TS=$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name '20*Z' -printf '%f\n' | sort | tail -1)
  else
    TS=$(aws_ s3 ls "s3://$BUCKET/backups/" | awk '/PRE 20/ {sub("/","",$2); print $2}' | sort | tail -1)
  fi
  [ -n "$TS" ] || fail "no backups found"
fi
if [ "$FROM_LOCAL" = 1 ]; then
  SRC="$BACKUP_DIR/$TS"
else
  SRC="$BACKUP_DIR/restore-$TS"
  rm -rf "$SRC"; mkdir -p "$SRC"
  aws_ s3 cp --recursive --only-show-errors "s3://$BUCKET/backups/$TS/" "$SRC/"
fi
[ -f "$SRC/manifest.json" ] || fail "backup $TS not found in $SRC"
log "restoring backup $TS ($MODE mode) into database $TARGET_DB"

# 2. Integrity: every file must match the checksum taken at backup time.
( cd "$SRC" && sha256sum -c --quiet SHA256SUMS ) || fail "checksum mismatch: backup is damaged"
tar -tzf "$SRC/librechat-files.tar.gz" >/dev/null || fail "files archive is unreadable"
EXPECTED=$(sed -E 's/.*"counts":(\{[^}]*\}).*/\1/' "$SRC/manifest.json")

# 3. Restore.
if [ "$MODE" = live ]; then
  log "stopping $APP_CONTAINER (the site shows an error until it is back)"
  docker stop "$APP_CONTAINER" >/dev/null
  docker exec -i "$MONGO_CONTAINER" sh -c \
    'exec mongorestore --quiet --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip --numParallelCollections=1 --numInsertionWorkersPerCollection=1 --drop --nsInclude "LibreChat.*"' \
    < "$SRC/mongo-LibreChat.archive.gz"
  # Keep the current files beside the restored ones, in case they are needed.
  for d in images uploads; do
    [ -d "$DATA_DIR/librechat/$d" ] && mv "$DATA_DIR/librechat/$d" "$DATA_DIR/librechat/$d.before-restore-$TS"
  done
  tar -xzf "$SRC/librechat-files.tar.gz" -C "$DATA_DIR/librechat"
  chown -R 1000:1000 "$DATA_DIR/librechat" 2>/dev/null || true
else
  mongo_eval "db.getSiblingDB('$TARGET_DB').dropDatabase()" >/dev/null
  docker exec -i "$MONGO_CONTAINER" sh -c \
    'exec mongorestore --quiet --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip --numParallelCollections=1 --numInsertionWorkersPerCollection=1 --nsInclude "LibreChat.*" --nsFrom "LibreChat.*" --nsTo "LibreChat_restoretest.*"' \
    < "$SRC/mongo-LibreChat.archive.gz"
fi

# 4. Verify: the restored database must hold exactly what the backup recorded.
ACTUAL=$(collection_counts "$TARGET_DB")
log "expected counts: $EXPECTED"
log "restored counts: $ACTUAL"
[ "$ACTUAL" = "$EXPECTED" ] || fail "restored counts do not match the backup manifest"

if [ "$MODE" = live ]; then
  docker start "$APP_CONTAINER" >/dev/null
  log "started $APP_CONTAINER again"
else
  mongo_eval "db.getSiblingDB('$TARGET_DB').dropDatabase()" >/dev/null
  metric RestoreTestSuccess 1
fi
[ "$FROM_LOCAL" = 1 ] || rm -rf "$SRC"
log "restore $MODE of $TS OK in $(( $(date +%s) - START ))s (counts match the backup)"
