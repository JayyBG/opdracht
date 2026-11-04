#!/usr/bin/env bash
# Extra scenario – Hoge belasting: genereer veel sensorrecords in één keer.
# Gebruik: scenario6-hoge-belasting.sh [aantal records, standaard 1000, max 20000]
# Verwacht in logs/app.log:  INFO Generated 1000 sensor records duration_ms=.. (WARN vanaf 5000)
set -euo pipefail
source "$(dirname "$0")/common.sh"

count="${1:-1000}"

login "$GW_USER" "$GW_PASSWORD" > /dev/null
status=$(curl -s -o /dev/null -w '%{http_code}' -b "$COOKIES" -X POST \
  --data "count=$count" "$BASE_URL/test/load")
echo "POST /test/load count=$count -> HTTP $status (303 = gelukt)"
