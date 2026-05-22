#!/usr/bin/env bash
# =============================================================================
# Mint a Cube JWT for a given userId + game.
#
# Reads CUBEJS_API_SECRET from the environment (or from a sourced .env).
# Prints the token to stdout so callers can capture it:
#
#   export CUBE_TOKEN=$(bash examples/00_mint_jwt.sh 1001 ballistar)
#
# The token shape matches cube/cube.js checkAuth: { userId, game, iat }.
# =============================================================================

set -euo pipefail

USER_ID="${1:-}"
GAME="${2:-}"
if [[ -z "$USER_ID" || -z "$GAME" ]]; then
  echo "usage: $0 <userId> <game>" >&2
  echo "example: $0 1001 ballistar" >&2
  exit 2
fi

if [[ -z "${CUBEJS_API_SECRET:-}" ]]; then
  # Try sourcing .env if it sits next to this script's repo root.
  ENV_FILE="$(dirname "$0")/../.env"
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; . "$ENV_FILE"; set +a
  fi
fi

if [[ -z "${CUBEJS_API_SECRET:-}" ]]; then
  echo "error: CUBEJS_API_SECRET not set (and no .env found)" >&2
  exit 1
fi

node -e "
  const jwt = require('jsonwebtoken');
  const token = jwt.sign(
    { userId: process.env.USER_ID, game: process.env.GAME },
    process.env.CUBEJS_API_SECRET
  );
  process.stdout.write(token);
" USER_ID="$USER_ID" GAME="$GAME"
