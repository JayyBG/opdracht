# Gedeelde instellingen voor de scenarioscripts. Overschrijf met omgevingsvariabelen.
BASE_URL="${BASE_URL:-http://localhost:8080}"
GW_USER="${GW_USER:-admin}"
GW_PASSWORD="${GW_PASSWORD:-GridWatch2030!}"

COOKIES="$(mktemp)"
trap 'rm -f "$COOKIES"' EXIT

# login <gebruiker> <wachtwoord>  -> print HTTP-status (302 = gelukt, 401 = mislukt)
login() {
  curl -s -o /dev/null -w '%{http_code}' -c "$COOKIES" -b "$COOKIES" \
    --data-urlencode "username=$1" --data-urlencode "password=$2" "$BASE_URL/login"
}
