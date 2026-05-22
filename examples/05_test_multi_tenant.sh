#!/usr/bin/env bash
# =============================================================================
# Multi-tenant smoke test.
#
# For each supported game, mint a JWT for that game's analyst user, hit the
# Cube REST API with a tiny query, and confirm a result comes back. Then run
# one negative-path call: a ballistar-scoped user attempting a cfm query →
# expect HTTP 4xx with a "not allowed" error.
#
# Usage:
#   1. docker compose up -d
#   2. Copy cube/auth-users.example.json -> cube/auth-users.json
#   3. bash examples/05_test_multi_tenant.sh
# =============================================================================

set -euo pipefail
CUBE_URL="${CUBE_URL:-http://localhost:4000/cubejs-api/v1/load}"
MINT="$(dirname "$0")/00_mint_jwt.sh"

# userId -> game mapping must match cube/auth-users.example.json.
declare -A USER_FOR_GAME=(
  [ballistar]=1001
  [cfm]=1002
  [ptg]=1003
  [jus]=1004
)

QUERY='{"query":{"measures":["mf_users.user_count_approx"]}}'

call() {
  local label="$1"; local token="$2"; local expect="$3"
  echo
  echo "──────────────────────────────────────────────────────────────────────"
  echo "▶ $label"
  echo "──────────────────────────────────────────────────────────────────────"
  local http_code
  http_code=$(curl -sS -o /tmp/cube_resp.json -w '%{http_code}' \
    -X POST "$CUBE_URL" \
    -H "Authorization: $token" \
    -H "Content-Type: application/json" \
    -d "$QUERY")
  echo "HTTP $http_code"
  jq '.' /tmp/cube_resp.json || cat /tmp/cube_resp.json
  if [[ "$expect" == "ok" && "$http_code" != "200" ]]; then
    echo "FAIL: expected 200 for $label" >&2; exit 1
  fi
  if [[ "$expect" == "deny" && "$http_code" == "200" ]]; then
    echo "FAIL: expected non-200 for $label" >&2; exit 1
  fi
}

for game in ballistar cfm ptg jus; do
  user="${USER_FOR_GAME[$game]}"
  token=$(bash "$MINT" "$user" "$game")
  call "Q — user count for game=$game (userId=$user)" "$token" "ok"
done

# Negative path: ballistar user (1001) tries to query cfm.
token=$(bash "$MINT" 1001 cfm)
call "Q — cross-game DENY: ballistar user requests cfm" "$token" "deny"

echo
echo "Done. All 4 games returned data; cross-game request was rejected."
