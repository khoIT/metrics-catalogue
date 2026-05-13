#!/usr/bin/env bash
# Time corrected single-user queries directly against Trino (bypasses Cube).
# This isolates Trino latency from Cube planner overhead.
set -euo pipefail

U="${1:-3469728876293357568}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

run_block() {
  local name="$1"; local sql="$2"
  echo "── $name"
  for i in 1 2 3; do
    t0=$(date +%s.%N)
    python3 "$SCRIPT_DIR/trino_q.py" "$sql" >/tmp/trino_out_$i.tsv 2>/tmp/trino_err_$i.log
    t1=$(date +%s.%N)
    rows=$(($(wc -l </tmp/trino_out_$i.tsv) - 1))
    elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b - a}')
    printf "  run %d: %ss  rows=%s\n" "$i" "$elapsed" "$rows"
  done
  echo
}

run_block "A. mf_users (profile, 1 row)" \
  "SELECT user_id, ingame_total_recharge_value_vnd, ingame_total_active_days, ingame_max_active_role_level
   FROM cfm_vn.mf_users WHERE user_id = '$U'"

run_block "B. std_ingame_user_active_daily (30 days)" \
  "SELECT log_date, ingame_last_active_server_id, ingame_max_active_role_level
   FROM cfm_vn.std_ingame_user_active_daily
   WHERE user_id = '$U' ORDER BY log_date DESC LIMIT 30"

run_block "C. std_ingame_user_recharge_daily (30 days)" \
  "SELECT log_date, ingame_total_recharge_value_vnd, ingame_total_recharge_transaction_id
   FROM cfm_vn.std_ingame_user_recharge_daily
   WHERE user_id = '$U' ORDER BY log_date DESC LIMIT 30"

run_block "D. etl_ingame_recharge (raw, 30 transactions)" \
  "SELECT transaction_id, recharge_time, charged_value, payment_channel
   FROM cfm_vn.etl_ingame_recharge
   WHERE account_id = '$U' ORDER BY recharge_time DESC LIMIT 30"
