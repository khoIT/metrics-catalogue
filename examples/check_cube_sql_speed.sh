#!/usr/bin/env bash
# Run the exact SQL Cube emits, directly against Trino. If THIS is slow,
# the bottleneck is Cube's SQL shape (GROUP BY + CAST wrapping). If this is
# fast, the bottleneck is in Cube's own pipeline/scheduler.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
U=3468067543004487680

run() {
  local name="$1"; local sql="$2"
  echo "── $name"
  for i in 1 2 3; do
    t0=$(date +%s.%N)
    python3 "$SCRIPT_DIR/trino_q.py" "$sql" > /tmp/co.tsv 2>&1 || cat /tmp/co.tsv
    t1=$(date +%s.%N)
    rows=$(( $(wc -l < /tmp/co.tsv) - 1 ))
    elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b - a}')
    printf "  run %d: %ss  rows=%s\n" "$i" "$elapsed" "$rows"
  done
  echo
}

run "Profile (Cube-shape: GROUP BY 1..20)" \
"SELECT \"mf_users\".user_id, \"mf_users\".unified_first_country_code, \"mf_users\".unified_first_os_platform,
        CAST(date_add('minute', timezone_minute(CAST(\"mf_users\".install_date AS TIMESTAMP) AT TIME ZONE 'UTC'), date_add('hour', timezone_hour(CAST(\"mf_users\".install_date AS TIMESTAMP) AT TIME ZONE 'UTC'), CAST(\"mf_users\".install_date AS TIMESTAMP))) AS TIMESTAMP),
        \"mf_users\".media_source, \"mf_users\".ingame_total_active_days, \"mf_users\".ingame_total_recharge_value_vnd
FROM cfm_vn.mf_users AS \"mf_users\"
WHERE \"mf_users\".user_id = '$U'
GROUP BY 1,2,3,4,5,6,7 ORDER BY 1 ASC LIMIT 1"

run "Profile (clean: no GROUP BY)" \
"SELECT user_id, unified_first_country_code, unified_first_os_platform, install_date,
        media_source, ingame_total_active_days, ingame_total_recharge_value_vnd
FROM cfm_vn.mf_users WHERE user_id = '$U' LIMIT 1"

run "Recharge timeline (Cube-shape)" \
"SELECT CAST(date_add('minute', timezone_minute(CAST(\"u\".log_date AS TIMESTAMP) AT TIME ZONE 'UTC'), date_add('hour', timezone_hour(CAST(\"u\".log_date AS TIMESTAMP) AT TIME ZONE 'UTC'), CAST(\"u\".log_date AS TIMESTAMP))) AS TIMESTAMP),
        \"u\".ingame_last_recharge_payment_channel, \"u\".ingame_last_recharge_product_id, \"u\".ingame_total_recharge_value_vnd, \"u\".ingame_total_recharge_transaction_id, \"u\".ingame_last_recharge_vip_level
FROM cfm_vn.std_ingame_user_recharge_daily \"u\"
WHERE \"u\".user_id = '$U'
GROUP BY 1,2,3,4,5,6 ORDER BY 1 DESC LIMIT 60"

run "Recharge timeline (clean)" \
"SELECT log_date, ingame_last_recharge_payment_channel, ingame_last_recharge_product_id, ingame_total_recharge_value_vnd, ingame_total_recharge_transaction_id, ingame_last_recharge_vip_level
FROM cfm_vn.std_ingame_user_recharge_daily
WHERE user_id = '$U' ORDER BY log_date DESC LIMIT 60"
