#!/usr/bin/env bash
# Scenario 1 – Inloggen: eerst een onbekende gebruiker, dan een fout wachtwoord, daarna succesvol.
# Verwacht in logs/app.log:
#   WARN Unknown user adminx ip=...
#   WARN Invalid password for user admin ip=...
#   INFO User admin logged in ip=...
set -euo pipefail
source "$(dirname "$0")/common.sh"

status=$(login "${GW_USER}x" "$GW_PASSWORD")
echo "1. Onbekende gebruiker ${GW_USER}x -> HTTP $status (401 = mislukt)"

status=$(login "$GW_USER" "verkeerd-wachtwoord")
echo "2. Fout wachtwoord voor $GW_USER  -> HTTP $status (401 = mislukt)"

status=$(login "$GW_USER" "$GW_PASSWORD")
echo "3. Juiste gegevens voor $GW_USER  -> HTTP $status (302 = gelukt)"
