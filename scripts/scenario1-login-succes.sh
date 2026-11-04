#!/usr/bin/env bash
# Scenario 1 – Gebruiker logt succesvol in.
# Verwacht in logs/app.log:  INFO User admin logged in ip=...
set -euo pipefail
source "$(dirname "$0")/common.sh"

status=$(login "$GW_USER" "$GW_PASSWORD")
echo "Login als $GW_USER -> HTTP $status (302 = gelukt)"
