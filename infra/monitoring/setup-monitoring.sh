#!/usr/bin/env bash
# Creates (or updates) all monitoring for Kapé Lumen. Run from your PC in Git Bash with the
# admin profile (AWS_PROFILE=kape). Safe to run again: every call overwrites the old version.
#
#   ./infra/monitoring/setup-monitoring.sh
#
#   1. Metric filters: turn brew-gateway and Caddy log lines into metrics (KapeLumen/*).
#   2. 10 alarms, all emailing the kape-alerts topic (and emailing again when they recover).
#   3. The "kape-lumen" CloudWatch dashboard.
# Cost: 10 alarms and 3 dashboards are inside the CloudWatch free tier.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash: keep "/kape/gateway" as it is

REGION=ap-southeast-1
cd "$(dirname "$0")"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TOPIC=arn:aws:sns:$REGION:$ACCOUNT_ID:kape-alerts
INSTANCE_ID=$(aws ec2 describe-instances --region $REGION \
  --filters Name=tag:Name,Values=kape-lumen Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
[ "$INSTANCE_ID" != None ] || { echo "No running instance tagged Name=kape-lumen" >&2; exit 1; }
SITE=$(aws ssm get-parameter --region $REGION --name /kape-lumen/env/SITE_ADDRESS --query Parameter.Value --output text)
echo "Account $ACCOUNT_ID, instance $INSTANCE_ID, site $SITE"

# ---------------------------------------------------------------- 1. metric filters
filter() { # log-group filter-name pattern metric-name value [unit]
  aws logs put-metric-filter --region $REGION --log-group-name "$1" --filter-name "$2" \
    --filter-pattern "$3" \
    --metric-transformations "[{\"metricName\":\"$4\",\"metricNamespace\":\"KapeLumen\",\"metricValue\":\"$5\",\"defaultValue\":0,\"unit\":\"${6:-Count}\"}]"
  echo "  filter $2 -> KapeLumen/$4"
}
echo "Metric filters:"
filter /kape/gateway kape-gateway-requests '{ $.event = "chat_request" }' GatewayRequests 1
filter /kape/gateway kape-gateway-errors '{ $.event = "chat_request" && $.success IS FALSE }' GatewayErrors 1
filter /kape/gateway kape-gateway-empty '{ $.event = "chat_request" && $.emptyAnswer IS TRUE }' GatewayEmptyAnswers 1
filter /kape/caddy kape-http-requests '{ $.msg = "handled request" }' HttpRequests 1
filter /kape/caddy kape-http-5xx '{ $.msg = "handled request" && $.status >= 500 }' Http5xx 1
# Latency: no defaultValue, otherwise quiet minutes would drag the average down to 0.
aws logs put-metric-filter --region $REGION --log-group-name /kape/gateway --filter-name kape-gateway-latency \
  --filter-pattern '{ $.event = "chat_request" && $.success IS TRUE }' \
  --metric-transformations '[{"metricName":"GatewayLatencyMs","metricNamespace":"KapeLumen","metricValue":"$.durationMs","unit":"Milliseconds"}]'
echo "  filter kape-gateway-latency -> KapeLumen/GatewayLatencyMs"

# ---------------------------------------------------------------- 2. alarms
ALARMS=()
alarm() { # name description [put-metric-alarm options...]
  local name=$1 desc=$2; shift 2
  aws cloudwatch put-metric-alarm --region $REGION --alarm-name "$name" --alarm-description "$desc" \
    --ok-actions "$TOPIC" --tags Key=Project,Value=SAM10 "$@"
  ALARMS+=("arn:aws:cloudwatch:$REGION:$ACCOUNT_ID:alarm:$name")
  echo "  alarm $name"
}
# The CloudWatch agent adds its own dimensions; read them instead of guessing.
agent_dims() { # metric
  local d
  d=$(aws cloudwatch list-metrics --region $REGION --namespace CWAgent --metric-name "$1" \
      --dimensions Name=InstanceId,Value=$INSTANCE_ID --query 'Metrics[0].Dimensions' --output json)
  if [ "$d" = null ]; then
    echo "  WARNING: no CWAgent $1 metric yet for $INSTANCE_ID; using InstanceId only" >&2
    d="[{\"Name\":\"InstanceId\",\"Value\":\"$INSTANCE_ID\"}]"
  fi
  echo "$d"
}
EC2="--namespace AWS/EC2 --dimensions Name=InstanceId,Value=$INSTANCE_ID"
echo "Alarms:"

alarm kape-site-down \
  "Customers cannot reach https://$SITE (3 failed checks in a row, or no checks at all = instance down). Runbook: docs/DEPLOY-AWS.md > When an alarm fires." \
  --alarm-actions "$TOPIC" --namespace KapeLumen --metric-name SiteUp --statistic Minimum \
  --period 60 --evaluation-periods 3 --datapoints-to-alarm 3 --threshold 1 \
  --comparison-operator LessThanThreshold --treat-missing-data breaching

alarm kape-ec2-hardware-check \
  "AWS reports a problem with the host hardware/network under our instance. Action: EC2 auto-recover moves it to healthy hardware (same IP, same disk)." \
  --alarm-actions "$TOPIC" "arn:aws:automate:$REGION:ec2:recover" $EC2 --metric-name StatusCheckFailed_System \
  --statistic Maximum --period 60 --evaluation-periods 2 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold

alarm kape-ec2-os-check \
  "The instance's operating system stopped responding (e.g. out of memory, kernel hang). Action: automatic reboot." \
  --alarm-actions "$TOPIC" "arn:aws:swf:$REGION:$ACCOUNT_ID:action/actions/AWS_EC2.InstanceId.Reboot/1.0" $EC2 \
  --metric-name StatusCheckFailed_Instance --statistic Maximum --period 60 --evaluation-periods 3 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold

alarm kape-cpu-high \
  "CPU above 80% for 15 minutes. On a t3.small this also burns CPU credits; when they run out the server slows down." \
  --alarm-actions "$TOPIC" $EC2 --metric-name CPUUtilization --statistic Average \
  --period 300 --evaluation-periods 3 --threshold 80 --comparison-operator GreaterThanThreshold

alarm kape-memory-high \
  "Memory above 85% for 10 minutes. Next step is swapping, then containers being killed." \
  --alarm-actions "$TOPIC" --namespace CWAgent --metric-name mem_used_percent --dimensions "$(agent_dims mem_used_percent)" \
  --statistic Average --period 300 --evaluation-periods 2 --threshold 85 --comparison-operator GreaterThanThreshold

alarm kape-disk-high \
  "Root disk above 80%. At 100% MongoDB stops writing and the site breaks. Check docker images, logs and /opt/kape/backups." \
  --alarm-actions "$TOPIC" --namespace CWAgent --metric-name disk_used_percent --dimensions "$(agent_dims disk_used_percent)" \
  --statistic Average --period 300 --evaluation-periods 1 --threshold 80 --comparison-operator GreaterThanThreshold

alarm kape-answers-failing \
  "3 or more customer questions failed in 5 minutes (Gemini error, quota, bad key or gateway fault). See the gateway log widget on the dashboard." \
  --alarm-actions "$TOPIC" --namespace KapeLumen --metric-name GatewayErrors --statistic Sum \
  --period 300 --evaluation-periods 1 --threshold 3 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching

alarm kape-answers-slow \
  "The slowest 10% of answers took over 10 seconds, in 2 of the last 3 five-minute periods." \
  --alarm-actions "$TOPIC" --namespace KapeLumen --metric-name GatewayLatencyMs --extended-statistic p90 \
  --period 300 --evaluation-periods 3 --datapoints-to-alarm 2 --threshold 10000 \
  --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching

alarm kape-http-5xx \
  "5 or more server errors (HTTP 5xx) served to browsers in 5 minutes." \
  --alarm-actions "$TOPIC" --namespace KapeLumen --metric-name Http5xx --statistic Sum \
  --period 300 --evaluation-periods 1 --threshold 5 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching

alarm kape-backup-missing \
  "No successful nightly backup in the last 24 hours (backup failed, or did not run at all)." \
  --alarm-actions "$TOPIC" --namespace KapeLumen --metric-name BackupSuccess --statistic Sum \
  --period 86400 --evaluation-periods 1 --threshold 1 --comparison-operator LessThanThreshold \
  --treat-missing-data breaching

# ---------------------------------------------------------------- 3. dashboard
arns=$(printf '"%s",' "${ALARMS[@]}"); arns=${arns%,}
OUT=dashboard.rendered.json   # gitignored (contains the account ID)
sed -e "s|\"ALARM_ARNS\"|$arns|" -e "s|INSTANCE_ID|$INSTANCE_ID|g" -e "s|REGION|$REGION|g" \
    -e "s|SITE_ADDRESS|$SITE|g" dashboard.json > $OUT
aws cloudwatch put-dashboard --region $REGION --dashboard-name kape-lumen --dashboard-body file://$OUT \
  --query 'DashboardValidationMessages' --output text
echo "Dashboard: https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#dashboards/dashboard/kape-lumen"
echo
aws cloudwatch describe-alarms --region $REGION --alarm-name-prefix kape- \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output table
