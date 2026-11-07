#!/usr/bin/env bash
# Is the site up, as a customer sees it? Run by cron every minute.
# Fetches https://<site>/health through the public address (DNS, TLS, Caddy and LibreChat all
# have to work) and publishes KapeLumen/SiteUp = 1 or 0. The kape-site-down alarm also treats
# MISSING data as down, so it fires if the whole instance dies and this script stops reporting.
# Quiet on success; failures go to the automation log.
JOB=probe
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

SITE=$(env_get SITE_ADDRESS)
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$SITE/health" || true)
if [ "$code" = 200 ]; then
  metric SiteUp 1
else
  log "site check failed: https://$SITE/health returned ${code:-no answer}" >> "$LOG_FILE"
  metric SiteUp 0
fi
