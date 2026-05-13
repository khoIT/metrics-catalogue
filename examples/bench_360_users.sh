#!/usr/bin/env bash
# Run the 360 fan-out cold against 3 distinct user_ids (proves real Trino path,
# not just a single-user cache hit) and again warm.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

USERS=(3468067543004487680 3468091043329875968 3468255228814524416 3468261029152186368)

summarize() {
  python3 -c "
import json,sys
d = json.load(open('/tmp/out.json'))
print('  timings_ms:', d['_timings_ms'])
print('  total_ms:', d['_total_ms'])
rows = {k: (len(v) if isinstance(v,list) else v) for k,v in d.items() if not k.startswith('_')}
print('  rows:', rows)
"
}

echo "============================================================"
echo "Pass 1 — cold (or partially cold) for 3 distinct users"
echo "============================================================"
for U in "${USERS[@]}"; do
  echo "── user $U"
  python3 "$SCRIPT_DIR/04_user_360_fanout.py" "$U" >/tmp/out.json
  summarize
done

echo
echo "============================================================"
echo "Pass 2 — warm (same 3 users, repeated)"
echo "============================================================"
for U in "${USERS[@]}"; do
  echo "── user $U"
  python3 "$SCRIPT_DIR/04_user_360_fanout.py" "$U" >/tmp/out.json
  summarize
done
