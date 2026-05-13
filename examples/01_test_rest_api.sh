#!/usr/bin/env bash
# =============================================================================
# REST API smoke tests for the ballistar_vn semantic layer
#
# Cube REST API takes a JSON `query` object describing what you want, then
# compiles & executes against Trino (or a matching pre-aggregation). It is
# the simplest API for LLM/MCP integration — easy to template, easy to parse.
#
# Usage:
#   1. Make sure docker compose is up and Trino credentials in .env are valid.
#   2. Mint a dev JWT (in dev mode, Cube also accepts CUBEJS_API_SECRET as token):
#        export CUBE_TOKEN=$(node -e "console.log(require('jsonwebtoken').sign({}, 'local-dev-secret-change-me-in-prod-please-32chars'))")
#      Or for quick testing in CUBEJS_DEV_MODE=true, you can just use the secret directly.
#   3. bash 01_test_rest_api.sh
# =============================================================================

set -euo pipefail
CUBE_URL="${CUBE_URL:-http://localhost:4000/cubejs-api/v1/load}"
CUBE_TOKEN="${CUBE_TOKEN:-local-dev-secret-change-me-in-prod-please-32chars}"

run() {
  local name="$1"; local payload="$2"
  echo
  echo "──────────────────────────────────────────────────────────────────────"
  echo "▶ $name"
  echo "──────────────────────────────────────────────────────────────────────"
  curl -sS -X POST "$CUBE_URL" \
    -H "Authorization: $CUBE_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" | jq '.'
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Total user count by country (uses pre-aggregation by_country_os_payer)
# ─────────────────────────────────────────────────────────────────────────────
run "Q1 — User count by country (top 10)" '{
  "query": {
    "measures": ["user_360.user_count_approx"],
    "dimensions": ["user_360.country"],
    "order": { "user_360.user_count_approx": "desc" },
    "limit": 10
  }
}'

# ─────────────────────────────────────────────────────────────────────────────
# 2. Payer tier breakdown for VN users
# ─────────────────────────────────────────────────────────────────────────────
run "Q2 — Payer tier breakdown (VN)" '{
  "query": {
    "measures": [
      "user_360.user_count_approx",
      "user_360.ltv_total_vnd",
      "user_360.arppu_vnd"
    ],
    "dimensions": ["user_360.payer_tier"],
    "segments": ["user_360.vn_users"]
  }
}'

# ─────────────────────────────────────────────────────────────────────────────
# 3. Audience build — VN whales who are at risk (return user_id list)
# This is the "segmentation" use case: dimensions only, no measures, get user list
# ─────────────────────────────────────────────────────────────────────────────
run "Q3 — Segment: VN whales at risk (user list)" '{
  "query": {
    "dimensions": [
      "user_360.user_id",
      "user_360.ltv_vnd",
      "user_360.days_since_last_active",
      "user_360.lifecycle_stage"
    ],
    "segments": ["user_360.vn_users", "user_360.whales", "user_360.at_risk_paying"],
    "order": { "user_360.ltv_vnd": "desc" },
    "limit": 100
  }
}'

# ─────────────────────────────────────────────────────────────────────────────
# 4. DAU last 14 days by OS
# ─────────────────────────────────────────────────────────────────────────────
run "Q4 — DAU last 14d by OS" '{
  "query": {
    "measures": ["activity_metrics.dau"],
    "dimensions": ["activity_metrics.os_platform"],
    "timeDimensions": [
      {
        "dimension": "activity_metrics.log_date",
        "granularity": "day",
        "dateRange": "last 14 days"
      }
    ],
    "order": { "activity_metrics.log_date": "asc" }
  }
}'

# ─────────────────────────────────────────────────────────────────────────────
# 5. Revenue last 7d by payment channel
# ─────────────────────────────────────────────────────────────────────────────
run "Q5 — Revenue last 7d by channel" '{
  "query": {
    "measures": [
      "revenue_metrics.revenue_vnd",
      "revenue_metrics.transactions",
      "revenue_metrics.paying_users",
      "revenue_metrics.arppu_vnd"
    ],
    "dimensions": ["revenue_metrics.payment_channel"],
    "timeDimensions": [
      {
        "dimension": "revenue_metrics.recharge_time",
        "dateRange": "last 7 days"
      }
    ],
    "order": { "revenue_metrics.revenue_vnd": "desc" }
  }
}'

# ─────────────────────────────────────────────────────────────────────────────
# 6. Cross-cube: paying VN users active in last 7d (joins mf_users + active_daily)
#    Cube will plan: filter mf_users by segments, join active_daily on user_id,
#    filter active_daily by date, count distinct.
# ─────────────────────────────────────────────────────────────────────────────
run "Q6 — Paying VN users seen in last 7d (cross-cube)" '{
  "query": {
    "measures": ["mf_users.user_count_approx"],
    "segments": ["mf_users.vn_users", "mf_users.paying_lifetime"],
    "filters": [
      {
        "member": "active_daily.log_date",
        "operator": "afterDate",
        "values": ["2026-05-03"]
      }
    ]
  }
}'

# ─────────────────────────────────────────────────────────────────────────────
# 7. Funnel-ish: install -> first_active conversion by media_source
# ─────────────────────────────────────────────────────────────────────────────
run "Q7 — Install -> first_active conversion by media_source" '{
  "query": {
    "measures": [
      "mf_users.user_count_approx"
    ],
    "dimensions": ["mf_users.media_source", "mf_users.is_paying_user"],
    "filters": [
      {
        "member": "mf_users.install_date",
        "operator": "afterDate",
        "values": ["2026-04-01"]
      }
    ]
  }
}'

echo
echo "Done. Check the SQL Cube generated by adding ?explain=true or via Playground."
