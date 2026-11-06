#!/usr/bin/env bash
# Uploads the café knowledge base (content/*.md) to S3. Run from your PC after editing content.
# The bucket has versioning on, so every upload keeps the previous version (WS-C.3).
# brew-gateway re-reads S3 every 5 minutes, so no restart is needed.
#
#   ./infra/sync-content.sh <content-bucket-name>
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop it rewriting "/kape-lumen/..." into a Windows path
BUCKET=${1:?usage: sync-content.sh <content-bucket-name>}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

aws s3 sync "$ROOT/content/" "s3://$BUCKET/content/" --delete --exclude '*' --include '*.md' \
  --content-type 'text/markdown; charset=utf-8' --region ap-southeast-1
echo "Now in s3://$BUCKET/content/:"
aws s3 ls "s3://$BUCKET/content/" --region ap-southeast-1
