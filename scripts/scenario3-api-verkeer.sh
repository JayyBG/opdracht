#!/usr/bin/env bash
# Scenario 3 – Veel API-aanvragen in korte tijd.
# Gebruik: scenario3-api-verkeer.sh [aantal, standaard 50] [endpoint, standaard /api/stations]
# Verwacht in logs/app.log:  INFO GET /api/stations status=200 duration_ms=.. ip=...
set -euo pipefail
source "$(dirname "$0")/common.sh"

count="${1:-50}"
endpoint="${2:-/api/stations}"

echo "Verstuur $count verzoeken naar $BASE_URL$endpoint ..."
start=$(date +%s)
for ((i = 0; i < count; i++)); do
  curl -s -o /dev/null -w '%{http_code}\n' "$BASE_URL$endpoint" || echo "000"
done | sort | uniq -c | awk '{print "  HTTP " $2 ": " $1 "x"}'
echo "Klaar in $(( $(date +%s) - start )) seconden."
