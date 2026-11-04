#!/usr/bin/env bash
# Scenario 5 – Container wordt handmatig gestopt en na een tijdje weer gestart.
# Gebruik: scenario5-containeruitval.sh [container, standaard webapp] [seconden uit, standaard 30]
# Verwacht: webapp -> "INFO Application stopped" en daarna "INFO Application started".
#           database -> "ERROR Database connection failed" bij elk verzoek tijdens de uitval.
set -euo pipefail
source "$(dirname "$0")/common.sh"

container="${1:-webapp}"
downtime="${2:-30}"

echo "Stop container '$container' ..."
docker stop "$container" > /dev/null
echo "Healthcheck tijdens uitval: HTTP $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE_URL/health" || true)"

echo "Wacht $downtime seconden ..."
sleep "$downtime"

echo "Start container '$container' ..."
docker start "$container" > /dev/null
for _ in $(seq 1 30); do
  status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$BASE_URL/health" || true)
  [ "$status" = "200" ] && break
  sleep 1
done
echo "Healthcheck na herstart: HTTP $status"
