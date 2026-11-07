#!/usr/bin/env bash
# (Re)deploys Kapé Lumen on the EC2 instance: pull the latest code, rebuild .env from SSM,
# and bring the stack up. Safe to run any time.
#   sudo /opt/kape/app/infra/deploy.sh
set -euo pipefail
exec > >(tee -a /var/log/kape-deploy.log) 2>&1
echo "=== deploy started $(date -u +%FT%TZ) ==="

APP_DIR=/opt/kape/app
cd "$APP_DIR"
if ! git pull --ff-only; then
  echo "deploy: git pull failed. Usually a file was edited directly on the server." >&2
  echo "        The repo is the source of truth: commit the fix on your PC and push, then run" >&2
  echo "        sudo git -C $APP_DIR checkout -- . && sudo $APP_DIR/infra/deploy.sh" >&2
  exit 1
fi
echo "commit: $(git rev-parse --short HEAD)"

export PATH="$PATH:/snap/bin"   # the AWS CLI is a snap
install -d -m 755 /opt/kape/data/{mongo,caddy,librechat/images,librechat/uploads,librechat/logs} /opt/kape/backups
# The LibreChat image runs as user "node" (uid 1000), so it must own the folders it writes to.
chown -R 1000:1000 /opt/kape/data/librechat
"$APP_DIR/infra/render-env.sh"

# Scheduled jobs (site probe, nightly backup, weekly restore test)
chmod +x "$APP_DIR"/infra/*.sh "$APP_DIR"/infra/ops/*.sh
install -m 644 -o root -g root "$APP_DIR/infra/cron/kape-lumen" /etc/cron.d/kape-lumen
touch /var/log/kape-automation.log

cd "$APP_DIR/infra"
docker compose --env-file /opt/kape/.env up -d --build --remove-orphans
docker compose --env-file /opt/kape/.env ps

echo "=== deploy finished $(date -u +%FT%TZ) ==="
