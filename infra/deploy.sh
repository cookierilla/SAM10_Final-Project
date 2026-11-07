#!/usr/bin/env bash
# (Re)deploys Kapé Lumen on the EC2 instance: pull the latest code, rebuild .env from SSM,
# and bring the stack up. Safe to run any time.
#   sudo /opt/kape/app/infra/deploy.sh
set -euo pipefail
exec > >(tee -a /var/log/kape-deploy.log) 2>&1
echo "=== deploy started $(date -u +%FT%TZ) ==="

APP_DIR=/opt/kape/app
cd "$APP_DIR"
git pull --ff-only
echo "commit: $(git rev-parse --short HEAD)"

export PATH="$PATH:/snap/bin"   # the AWS CLI is a snap
install -d -m 755 /opt/kape/data/{mongo,caddy,librechat/images,librechat/uploads,librechat/logs} /opt/kape/backups
# The LibreChat image runs as user "node" (uid 1000), so it must own the folders it writes to.
chown -R 1000:1000 /opt/kape/data/librechat
"$APP_DIR/infra/render-env.sh"

cd "$APP_DIR/infra"
docker compose --env-file /opt/kape/.env up -d --build --remove-orphans
docker compose --env-file /opt/kape/.env ps

echo "=== deploy finished $(date -u +%FT%TZ) ==="
