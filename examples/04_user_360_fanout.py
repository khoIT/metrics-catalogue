#!/usr/bin/env python3
"""
360-view fan-out: fire all four single-user queries in parallel and merge.

This is the recommended client shape for the "search all data for 1 user in
under a second" use case. Wall-clock is bounded by the slowest of the four
calls (not the sum), so the total budget stays comfortably under 1s.

Usage:
    python3 04_user_360_fanout.py 3469728876293357568

Output: one JSON object with keys {profile, activity, recharge, transactions}
plus per-leg latencies for debugging.
"""
from __future__ import annotations

import concurrent.futures
import json
import os
import sys
import time
import urllib.error
import urllib.request

CUBE_URL = os.environ.get("CUBE_URL", "http://localhost:4000/cubejs-api/v1/load")
CUBE_TOKEN = os.environ.get(
    "CUBE_TOKEN", "local-dev-secret-change-me-in-prod-please-32chars"
)


def cube_query(payload: dict, max_wait_s: float = 30.0) -> tuple[dict, float]:
    """POST to Cube. Cube uses long-polling: a query that's still computing
    returns HTTP 200 with {"error":"Continue wait"} — keep re-posting the
    same payload until we get data, an error, or the deadline."""
    data = json.dumps(payload).encode()
    headers = {"Authorization": CUBE_TOKEN, "Content-Type": "application/json"}
    t0 = time.perf_counter()
    while True:
        req = urllib.request.Request(CUBE_URL, data=data, headers=headers)
        try:
            body = json.loads(urllib.request.urlopen(req).read())
        except urllib.error.HTTPError as e:
            try:
                body = json.loads(e.read())
            except Exception:
                body = {"error": f"HTTP {e.code}: {e.reason}"}
        if body.get("error") == "Continue wait":
            if time.perf_counter() - t0 > max_wait_s:
                break
            time.sleep(0.1)
            continue
        break
    return body, time.perf_counter() - t0


def queries_for(user_id: str) -> dict[str, dict]:
    """Build the four parallel queries that make up the 360 view."""
    eq = {"member": "{view}.user_id", "operator": "equals", "values": [user_id]}

    profile = {
        "query": {
            "dimensions": [
                "user_profile.user_id",
                "user_profile.country",
                "user_profile.os_platform",
                "user_profile.install_date",
                "user_profile.media_source",
                "user_profile.first_active_date",
                "user_profile.last_active_date",
                "user_profile.total_active_days",
                "user_profile.max_role_level",
                "user_profile.last_role_class",
                "user_profile.last_server_id",
                "user_profile.ltv_vnd",
                "user_profile.ltv_30d_vnd",
                "user_profile.lifetime_txn_count",
                "user_profile.txn_count_30d",
                "user_profile.max_vip_level",
                "user_profile.payer_tier",
                "user_profile.lifecycle_stage",
                "user_profile.days_since_last_active",
                "user_profile.days_since_last_recharge",
            ],
            "filters": [{**eq, "member": "user_profile.user_id"}],
            "limit": 1,
        }
    }

    activity = {
        "query": {
            "dimensions": [
                "user_activity_timeline.log_date",
                "user_activity_timeline.server_id",
                "user_activity_timeline.role_id",
                "user_activity_timeline.role_class",
                "user_activity_timeline.max_role_level",
                "user_activity_timeline.online_time_sec",
                "user_activity_timeline.is_recharge_day",
            ],
            "filters": [{**eq, "member": "user_activity_timeline.user_id"}],
            "order": {"user_activity_timeline.log_date": "desc"},
            "limit": 60,
        }
    }

    recharge = {
        "query": {
            "dimensions": [
                "user_recharge_timeline.log_date",
                "user_recharge_timeline.payment_channel",
                "user_recharge_timeline.product_id",
                "user_recharge_timeline.revenue_vnd",
                "user_recharge_timeline.txn_count",
                "user_recharge_timeline.vip_level",
            ],
            "filters": [{**eq, "member": "user_recharge_timeline.user_id"}],
            "order": {"user_recharge_timeline.log_date": "desc"},
            "limit": 60,
        }
    }

    transactions = {
        "query": {
            "dimensions": [
                "user_transactions.transaction_id",
                "user_transactions.recharge_time",
                "user_transactions.payment_channel",
                "user_transactions.product_id",
                "user_transactions.value_vnd",
                "user_transactions.txn_value_band_vnd",
                "user_transactions.is_first_recharge",
            ],
            "filters": [{**eq, "member": "user_transactions.user_id"}],
            "order": {"user_transactions.recharge_time": "desc"},
            "limit": 50,
        }
    }

    return {
        "profile": profile,
        "activity": activity,
        "recharge": recharge,
        "transactions": transactions,
    }


def user_360(user_id: str) -> dict:
    qs = queries_for(user_id)
    out: dict = {}
    timings: dict[str, float] = {}

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(qs)) as ex:
        futures = {ex.submit(cube_query, payload): name for name, payload in qs.items()}
        for fut in concurrent.futures.as_completed(futures):
            name = futures[fut]
            body, dt = fut.result()
            timings[name] = round(dt * 1000, 1)
            if "error" in body:
                out[name] = {"error": body["error"]}
            else:
                out[name] = body.get("data", [])

    out["_timings_ms"] = timings
    return out


def main() -> int:
    user_id = sys.argv[1] if len(sys.argv) > 1 else "3469728876293357568"
    t0 = time.perf_counter()
    result = user_360(user_id)
    total_ms = round((time.perf_counter() - t0) * 1000, 1)
    result["_total_ms"] = total_ms
    print(json.dumps(result, indent=2, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
