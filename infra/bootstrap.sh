#!/usr/bin/env bash
# EC2 user-data for Ubuntu 24.04: runs once, as root, on the instance's first boot.
# Installs Docker, the AWS CLI and the CloudWatch agent, adds swap, clones the repo and deploys.
# Progress: /var/log/kape-bootstrap.log (also shipped to CloudWatch /kape/host).
set -euo pipefail
exec > >(tee -a /var/log/kape-bootstrap.log) 2>&1
echo "=== bootstrap started $(date -u +%FT%TZ) ==="

REPO_URL=https://github.com/cookierilla/SAM10_Final-Project.git
APP_DIR=/opt/kape/app
export DEBIAN_FRONTEND=noninteractive

# 1. Packages: Docker + Compose from Ubuntu's own repositories, AWS CLI from the official snap.
apt-get update -y
apt-get install -y docker.io docker-compose-v2 git curl jq
systemctl enable --now docker
snap install aws-cli --classic

# 2. 2 GB swap file: a safety net for a 2 GB instance (LibreChat build steps can spike memory).
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 3. CloudWatch agent: memory, disk and swap metrics + host log files (config is in the repo).
curl -fsSL -o /tmp/cwagent.deb https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i /tmp/cwagent.deb

# 4. Code
install -d -m 755 /opt/kape
[ -d "$APP_DIR/.git" ] || git clone "$REPO_URL" "$APP_DIR"
chmod +x "$APP_DIR"/infra/*.sh

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c "file:$APP_DIR/infra/cloudwatch-agent.json"

# 5. Deploy (pulls secrets from SSM, starts the containers)
"$APP_DIR/infra/deploy.sh"

echo "=== bootstrap finished $(date -u +%FT%TZ) ==="
