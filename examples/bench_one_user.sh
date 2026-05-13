#!/usr/bin/env bash
# Benchmark a single-user 360 lookup against the Cube REST API.
# Usage: USER_ID=<id> bash bench_one_user.sh   (defaults to a sample id)

set -euo pipefail

CUBE_URL="${CUBE_URL:-http://localhost:4000/cubejs-api/v1/load}"
CUBE_TOKEN="${CUBE_TOKEN:-local-dev-secret-change-me-in-prod-please-32chars}"
USER_ID="${USER_ID:-3367722220497485824}"

bench() {
  local name="$1"; local payload="$2"; local n="${3:-3}"
  echo "── $name"
  for i in $(seq 1 "$n"); do
    /usr/bin/time -f '  run %s: %e s' \
      curl -sS -o /tmp/cube_out.json -w '  http_total=%{time_total}s size=%{size_download}B\n' \
        -X POST "$CUBE_URL" \
        -H "Authorization: $CUBE_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload"
  done
  echo "  preagg_used=$(jq -c '.usedPreAggregations' /tmp/cube_out.json 2>/dev/null || echo '?')"
  echo "  rows=$(jq -c '.data | length' /tmp/cube_out.json 2>/dev/null || echo '?')"
  echo
}

# A. Profile (mf_users only) — wide row for one user_id
bench "A. Profile (mf_users only)" "$(cat <<JSON
{"query":{
  "dimensions":[
    "user_360.user_id","user_360.country","user_360.os_platform",
    "user_360.install_date","user_360.media_source","user_360.is_paid_install",
    "user_360.first_login_date","user_360.last_login_date","user_360.last_login_channel",
    "user_360.first_active_date","user_360.last_active_date","user_360.total_active_days",
    "user_360.max_role_level","user_360.max_fighting_power","user_360.last_role_class",
    "user_360.last_server_id","user_360.days_since_install","user_360.days_since_last_active",
    "user_360.days_since_last_recharge","user_360.first_recharge_date","user_360.last_recharge_date",
    "user_360.ltv_vnd","user_360.ltv_30d_vnd","user_360.ltv_iap_vnd","user_360.ltv_web_vnd",
    "user_360.lifetime_txn_count","user_360.txn_count_30d","user_360.max_vip_level",
    "user_360.payer_tier","user_360.lifecycle_stage"
  ],
  "filters":[{"member":"user_360.user_id","operator":"equals","values":["$USER_ID"]}],
  "limit":1
}}
JSON
)"

# B. Recharge history (event cube) for one user — last 50 transactions
bench "B. Recharge history (event scan)" "$(cat <<JSON
{"query":{
  "dimensions":[
    "revenue_metrics.recharge_time","revenue_metrics.payment_channel",
    "revenue_metrics.product_id","revenue_metrics.txn_value_band_vnd"
  ],
  "measures":["revenue_metrics.revenue_vnd","revenue_metrics.transactions"],
  "filters":[{"member":"recharge.user_id","operator":"equals","values":["$USER_ID"]}],
  "order":{"revenue_metrics.recharge_time":"desc"},
  "limit":50
}}
JSON
)"

# C. Activity history (event cube) for one user — last 50 active days
bench "C. Activity history (event scan)" "$(cat <<JSON
{"query":{
  "dimensions":[
    "activity_metrics.log_date","activity_metrics.server_id",
    "activity_metrics.country_code","activity_metrics.os_platform"
  ],
  "measures":["activity_metrics.rows"],
  "filters":[{"member":"active_daily.user_id","operator":"equals","values":["$USER_ID"]}],
  "order":{"activity_metrics.log_date":"desc"},
  "limit":50
}}
JSON
)"
