#!/usr/bin/env python3
"""
03_segment_dsl_compiler.py — minimal example of how an LLM/MCP layer can
compile a high-level "segment DSL" into a Cube REST API call.

This is the integration layer between natural-language audience requests
("VN whales who churned") and Cube. Three responsibilities:

  1. Resolve segment names + filter atoms into a Cube query JSON
  2. POST to Cube REST API
  3. Return user list (for activation) OR aggregate counts (for sizing)

Run:
  pip install requests
  python 03_segment_dsl_compiler.py
"""

import json
import os
import sys
from typing import Any

import requests

CUBE_URL = os.getenv("CUBE_URL", "http://localhost:4000/cubejs-api/v1/load")
CUBE_TOKEN = os.getenv(
    "CUBE_TOKEN",
    "local-dev-secret-change-me-in-prod-please-32chars",
)


def compile_segment_dsl(dsl: dict[str, Any], mode: str = "size") -> dict[str, Any]:
    """
    Compile a segment DSL document into a Cube REST query.

    DSL shape:
      {
        "view": "user_360",
        "segments": ["vn_users", "whales"],          # named, reusable filters
        "filters": [                                  # ad-hoc atoms
          {"field": "ltv_30d_vnd", "op": ">=", "value": 500000},
          {"field": "days_since_last_active", "op": "between", "value": [7, 30]}
        ],
        "output_fields": ["user_id", "ltv_vnd"]      # only used when mode=list
      }

    mode:
      "size" -> returns count + headline measures (audience sizing)
      "list" -> returns one row per user (audience export)
    """
    view = dsl["view"]
    segments = [f"{view}.{s}" for s in dsl.get("segments", [])]
    filters = [_compile_filter(view, f) for f in dsl.get("filters", [])]

    if mode == "size":
        return {
            "measures": [
                f"{view}.user_count_approx",
                f"{view}.paying_users",
                f"{view}.ltv_total_vnd",
                f"{view}.arppu_vnd",
            ],
            "segments": segments,
            "filters": filters,
        }
    elif mode == "list":
        fields = dsl.get("output_fields", ["user_id"])
        return {
            "dimensions": [f"{view}.{f}" for f in fields],
            "segments": segments,
            "filters": filters,
            "limit": dsl.get("limit", 10000),
            "order": dsl.get("order"),
        }
    else:
        raise ValueError(f"Unknown mode: {mode}")


def _compile_filter(view: str, atom: dict[str, Any]) -> dict[str, Any]:
    """Translate a DSL filter atom to Cube filter format."""
    op_map = {
        "=":      "equals",
        "!=":     "notEquals",
        ">":      "gt",
        ">=":     "gte",
        "<":      "lt",
        "<=":     "lte",
        "in":     "equals",
        "not_in": "notEquals",
        "between": "inDateRange",   # for time fields; for numeric, use gte+lte
        "is_null":     "notSet",
        "is_not_null": "set",
    }
    cube_op = op_map.get(atom["op"], atom["op"])
    out = {"member": f"{view}.{atom['field']}", "operator": cube_op}
    if "value" in atom:
        v = atom["value"]
        out["values"] = [str(x) for x in v] if isinstance(v, list) else [str(v)]
    return out


def query_cube(query: dict[str, Any]) -> dict[str, Any]:
    """POST to Cube REST and return parsed JSON."""
    resp = requests.post(
        CUBE_URL,
        headers={
            "Authorization": CUBE_TOKEN,
            "Content-Type": "application/json",
        },
        json={"query": query},
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()


# ─────────────────────────────────────────────────────────────────────────────
# Demo: a few realistic LLM-generated segment specs
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    demos = [
        {
            "name": "Size of VN paying users in last 30d",
            "dsl": {
                "view": "user_360",
                "segments": ["vn_users", "paying_recently_30d"],
            },
            "mode": "size",
        },
        {
            "name": "Export VN whales at risk for re-engagement campaign",
            "dsl": {
                "view": "user_360",
                "segments": ["vn_users", "whales", "at_risk_paying"],
                "output_fields": [
                    "user_id",
                    "ltv_vnd",
                    "days_since_last_active",
                    "last_role_class",
                ],
                "order": {"user_360.ltv_vnd": "desc"},
                "limit": 500,
            },
            "mode": "list",
        },
        {
            "name": "High-engagement minnows — upsell candidates",
            "dsl": {
                "view": "user_360",
                "segments": ["paying_lifetime", "high_level_players"],
                "filters": [
                    {"field": "ltv_vnd", "op": "<",  "value": 500000},
                    {"field": "ltv_vnd", "op": ">=", "value": 50000},
                    {"field": "days_since_last_active", "op": "<=", "value": 3},
                ],
            },
            "mode": "size",
        },
    ]

    for d in demos:
        print("=" * 70)
        print(f"▶ {d['name']}")
        print("=" * 70)
        query = compile_segment_dsl(d["dsl"], mode=d["mode"])
        print("Compiled Cube query:")
        print(json.dumps(query, indent=2))
        try:
            result = query_cube(query)
            print("\nResult (top 5 rows):")
            print(json.dumps(result.get("data", [])[:5], indent=2, default=str))
            print(f"\nTotal rows returned: {len(result.get('data', []))}")
        except requests.HTTPError as e:
            print(f"\n[error] {e}\n{e.response.text}", file=sys.stderr)
        print()
