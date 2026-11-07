# Shared helpers for the scripts in infra/ops/. Sourced, not run.
# Settings come from /opt/kape/.env (written by infra/render-env.sh). Every path can be
# overridden with an environment variable, which is how the scripts are tested locally.
set -Eeuo pipefail   # -E: the ERR trap also fires inside functions
export PATH="$PATH:/snap/bin"   # the AWS CLI is a snap on the instance

KAPE_ENV=${KAPE_ENV:-/opt/kape/.env}
MONGO_CONTAINER=${MONGO_CONTAINER:-chat-mongodb}
APP_CONTAINER=${APP_CONTAINER:-LibreChat}
BACKUP_DIR=${BACKUP_DIR:-/opt/kape/backups}
DATA_DIR=${DATA_DIR:-/opt/kape/data}
LOG_FILE=${LOG_FILE:-/var/log/kape-automation.log}
DRY_AWS=${DRY_AWS:-0}            # 1 = print AWS calls instead of making them (local tests)
DB_NAME=LibreChat
NAMESPACE=KapeLumen

# Read one value from the .env file without sourcing it (some values contain spaces and brackets).
env_get() { grep -E "^$1=" "$KAPE_ENV" | head -1 | cut -d= -f2-; }
REGION=$(env_get AWS_REGION || true); REGION=${REGION:-ap-southeast-1}

log() { echo "$(date -u +%FT%TZ) [${JOB:-ops}] $*"; }

# Send everything this script prints to the automation log too (shipped to CloudWatch /kape/host).
log_to_file() { exec > >(tee -a "$LOG_FILE") 2>&1; }

aws_() {
  if [ "$DRY_AWS" = 1 ]; then echo "  (dry-run) aws $*" >&2; return 0; fi
  aws --region "$REGION" "$@"
}

metric() { # name value [unit]
  aws_ cloudwatch put-metric-data --namespace "$NAMESPACE" --metric-name "$1" --value "$2" --unit "${3:-Count}"
}

alert() { # subject message
  [ "$DRY_AWS" = 1 ] && { echo "  (dry-run) ALERT: $1: $2" >&2; return 0; }
  local account
  account=$(aws --region "$REGION" sts get-caller-identity --query Account --output text)
  aws --region "$REGION" sns publish --topic-arn "arn:aws:sns:$REGION:$account:kape-alerts" \
    --subject "$1" --message "$2" >/dev/null
}

# Run JavaScript in mongosh inside the MongoDB container, authenticated as the root user.
# The password never leaves the container: it is the container's own MONGO_INITDB_ROOT_PASSWORD.
mongo_eval() { # js
  printf '%s\n' "$1" | docker exec -i "$MONGO_CONTAINER" sh -c \
    'cat > /tmp/kape-q.js && mongosh --quiet --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --file /tmp/kape-q.js; rc=$?; rm -f /tmp/kape-q.js; exit $rc'
}

# Document count per collection, as one line of JSON with sorted keys: {"conversations":3,...}
collection_counts() { # db
  mongo_eval "const d = db.getSiblingDB('$1'); const o = {};
d.getCollectionNames().filter(c => !c.startsWith('system.')).sort().forEach(c => { o[c] = d.getCollection(c).countDocuments(); });
print(JSON.stringify(o));"
}
