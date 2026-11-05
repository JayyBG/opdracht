#!/usr/bin/env bash
# Scenario 2 – Gebruiker voert meerdere keren een verkeerd wachtwoord in (brute force).
# Gebruik: scenario2-foute-logins.sh [aantal pogingen, standaard 15]
# Verwacht in logs/app.log:  WARN Invalid password for user admin ip=...
set -euo pipefail
source "$(dirname "$0")/common.sh"

attempts="${1:-15}"
passwords=(welkom123 test123 admin123 wachtwoord 123456 qwerty letmein)

for ((i = 0; i < attempts; i++)); do
  password="${passwords[i % ${#passwords[@]}]}"
  status=$(login "$GW_USER" "$password")
  echo "Poging $((i + 1)): $GW_USER / $password -> HTTP $status"
done
