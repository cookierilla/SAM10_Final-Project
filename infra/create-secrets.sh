#!/usr/bin/env bash
# Run ONCE from your own PC (Git Bash, with the AWS CLI signed in as your IAM user).
# Creates every secret the system needs in SSM Parameter Store as SecureString.
# Random secrets are generated here and never printed. The Gemini key is typed with input hidden.
#
#   ./infra/create-secrets.sh <content-bucket-name>
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop it rewriting "/kape-lumen/..." into a Windows path

REGION=ap-southeast-1
BUCKET=${1:?usage: create-secrets.sh <content-bucket-name>}
TAGS='Key=Project,Value=SAM10'

rand_hex() { openssl rand -hex "$1"; }

put_secret() { # name value
  aws ssm put-parameter --region "$REGION" --name "$1" --type SecureString --value "$2" \
    --tags $TAGS >/dev/null 2>&1 \
  || aws ssm put-parameter --region "$REGION" --name "$1" --type SecureString --value "$2" --overwrite >/dev/null
  echo "  stored $1 (SecureString)"
}

exists() { aws ssm get-parameter --region "$REGION" --name "$1" >/dev/null 2>&1; }

echo "Creating secrets under /kape-lumen/ in $REGION ..."

# LibreChat's own secrets. Its .env.example ships public default values; we must not use those.
for pair in "CREDS_KEY 32" "CREDS_IV 16" "JWT_SECRET 32" "JWT_REFRESH_SECRET 32" "GATEWAY_TOKEN 24" "MONGO_PASSWORD 24"; do
  set -- $pair
  if exists "/kape-lumen/env/$1"; then echo "  /kape-lumen/env/$1 already exists, kept"; else put_secret "/kape-lumen/env/$1" "$(rand_hex "$2")"; fi
done

# Not secret, but kept beside the others so the server can find it.
aws ssm put-parameter --region "$REGION" --name /kape-lumen/env/CONTENT_BUCKET --type String \
  --value "$BUCKET" --overwrite >/dev/null && echo "  stored /kape-lumen/env/CONTENT_BUCKET (String)"

if exists /kape-lumen/gemini-api-key; then
  echo "  /kape-lumen/gemini-api-key already exists, kept (rotate with: aws ssm put-parameter --overwrite ...)"
else
  read -r -s -p "Paste your Gemini API key (input hidden): " GEMINI_KEY; echo
  [ -n "$GEMINI_KEY" ] || { echo "No key entered, stopping." >&2; exit 1; }
  put_secret /kape-lumen/gemini-api-key "$GEMINI_KEY"
  unset GEMINI_KEY
fi

echo "Done. List (names only):"
aws ssm get-parameters-by-path --region "$REGION" --path /kape-lumen/ --recursive \
  --query 'Parameters[].[Name,Type]' --output table
