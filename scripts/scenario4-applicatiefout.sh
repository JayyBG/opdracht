#!/usr/bin/env bash
# Scenario 4 – Applicatiefout wordt gegenereerd.
# Verwacht in logs/app.log:  ERROR Test exception generated type=RuntimeError path=/test/error ...
set -euo pipefail
source "$(dirname "$0")/common.sh"

login "$GW_USER" "$GW_PASSWORD" > /dev/null
status=$(curl -s -o /dev/null -w '%{http_code}' -b "$COOKIES" -X POST "$BASE_URL/test/error")
echo "POST /test/error -> HTTP $status (500 = fout gegenereerd)"
