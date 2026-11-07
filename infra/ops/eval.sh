#!/usr/bin/env bash
# Nightly quality check: asks Lumen the labelled test questions (eval/test-questions.json) through
# the real gateway and model, scores the answers, and emails the pass rate to kape-alerts.
# Publishes KapeLumen/EvalPassRate (%) and KapeLumen/EvalErrors so the trend shows on the dashboard.
#
# Run by cron every night (infra/cron/kape-lumen). By hand:  sudo /opt/kape/app/infra/ops/eval.sh
# The questions also appear in the gateway's request metrics (about 10 extra requests a night).
JOB=eval
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"
log_to_file

GATEWAY_CONTAINER=${GATEWAY_CONTAINER:-brew-gateway}
EVAL_DIR=${EVAL_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/eval}
OUT="$BACKUP_DIR/eval-$(date -u +%Y%m%dT%H%M%SZ).json"
SITE=$(env_get SITE_ADDRESS || true)

fail() {
  trap - ERR
  log "FAILED: $*"
  metric EvalPassRate 0 Percent || true
  alert "Kape Lumen: nightly quality check could not run" "The nightly eval failed to run on $(hostname): $*" || true
  exit 1
}
trap 'fail "line $LINENO exited with status $?"' ERR

log "starting nightly eval ($(grep -c '"id"' "$EVAL_DIR/test-questions.json") questions)"
# The eval runs inside the gateway container: it already has Node and the gateway token,
# and the gateway port is not published to the host.
# Clear last run first (as root: docker cp files are root-owned), so a stale result is never reported.
docker exec -u root "$GATEWAY_CONTAINER" rm -rf /tmp/eval /tmp/eval-result.json
docker cp "$EVAL_DIR/." "$GATEWAY_CONTAINER:/tmp/eval"
# run-eval exits 1 when any question is not passed; that is a result to report, not a crash.
REPORT=$(docker exec "$GATEWAY_CONTAINER" node /tmp/eval/run-eval.mjs /tmp/eval/test-questions.json --json=/tmp/eval-result.json 2>&1) || true
echo "$REPORT"
docker cp "$GATEWAY_CONTAINER:/tmp/eval-result.json" "$OUT" 2>/dev/null || fail "the eval produced no result file"

SCORE=$(echo "$REPORT" | grep '^SCORE' | tail -1 || true)
[ -n "$SCORE" ] || fail "no SCORE line in the eval output"
RATE=$(echo "$SCORE" | sed -E 's/.*\(([0-9.]+)%\).*/\1/')
ERRORS=$(echo "$SCORE" | sed -E 's/.* ([0-9]+) errors.*/\1/')
NOT_PASSED=$(echo "$REPORT" | grep -E '^(FAIL|ERROR) ' | awk '{print $1, $2}' | paste -sd ',' - | sed 's/,/, /g' || true)

metric EvalPassRate "$RATE" Percent
metric EvalErrors "$ERRORS"
alert "Kape Lumen nightly check: $RATE% correct" "$SCORE

Not passed: ${NOT_PASSED:-none}
Site: https://$SITE
Full answers: $OUT on the instance, and CloudWatch /kape/host stream */automation."
log "eval done: $SCORE"

# Keep 14 nights of result files locally.
find "$BACKUP_DIR" -maxdepth 1 -name 'eval-*.json' -mtime +13 -delete
