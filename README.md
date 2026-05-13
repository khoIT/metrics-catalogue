# Ballistar VN — Cube Semantic Layer on Trino

Production-shaped Cube semantic layer for the `ballistar_vn` user master profile + event tables, designed for user segmentation and audience building. Sits on top of Trino, exposes REST / GraphQL / SQL APIs, and pre-aggregates hot queries into Cube Store.

```
┌───────────────────────────────────────────────────────────────────┐
│   LLM / MCP / BI tools / custom apps                              │
│   ─ POST /cubejs-api/v1/load     (REST, simplest for MCP)         │
│   ─ POST /cubejs-api/graphql     (GraphQL, type-safe)             │
│   ─ psql -h … -p 15432           (SQL API, BI tools connect here) │
└──────────────────────────────────┬────────────────────────────────┘
                                   │
                  ┌────────────────▼─────────────────┐
                  │  Cube API (semantic layer)       │
                  │  ─ YAML schema (this repo)       │
                  │  ─ Query planner + cache         │
                  │  ─ Pre-agg matcher               │
                  └────────────────┬─────────────────┘
                                   │
                ┌──────────────────┼──────────────────┐
                ▼                                     ▼
       ┌───────────────────┐               ┌───────────────────────┐
       │ Cube Store        │               │ Trino                 │
       │ (pre-aggregations │               │ (raw + curated tables │
       │  materialized)    │               │  ballistar_vn.*)      │
       └───────────────────┘               └───────────────────────┘
```

## What's in here

```
ballistar-cube-semantic/
├── docker-compose.yml          # Cube API + Cube Store router/worker
├── .env.example                # Trino + Cube config (cp to .env)
├── cube/
│   └── model/
│       ├── cubes/
│       │   ├── mf_users.yml         # Master profile feature store (1 row/user)
│       │   ├── active_daily.yml     # Daily activity events
│       │   └── recharge.yml         # Recharge transaction events
│       └── views/
│           └── user_360.yml         # Entity-first view + 2 metric views
└── examples/
    ├── 01_test_rest_api.sh          # 7 curl-based smoke tests
    ├── 02_test_sql_api.sql          # SQL API equivalents
    └── 03_segment_dsl_compiler.py   # LLM-friendly DSL → Cube compiler demo
```

## Design choices

**Three cubes mirror the three data shapes.** `mf_users` is the wide profile store (one row per user, lifetime + 30d rolling pre-aggregated). `active_daily` and `recharge` are events. Cube routes queries automatically: a question Cube can answer from `mf_users` alone never scans the event tables.

**Views are the consumption surface.** `user_360` is the main entity-first view exposing `mf_users` for segmentation. `revenue_metrics` and `activity_metrics` are metric-first views for time-series dashboards. LLM/MCP and BI tools should query views, not raw cubes — views can be re-shaped without breaking consumers.

**Segments encode reusable audience logic.** `vn_users`, `whales`, `at_risk_paying`, `paid_install`, etc. are predefined named filters. They self-document the audience and are amenable to natural-language matching ("VN whales who churned" → `vn_users + whales + at_risk_paying`).

**Derived classifications live as `case` dimensions.** `payer_tier` (whale/dolphin/minnow/non_payer), `lifecycle_stage` (active_today/active_7d/.../churned). These compile to SQL `CASE` expressions and can be both grouped by AND filtered on.

**Pre-aggregations target known hot queries.** `mf_users.by_country_os_payer` (cohort breakdown), `active_daily.dau_by_country_os` (DAU dashboards), `recharge.revenue_daily` (revenue by channel). Partitioned monthly, refreshed incrementally every 30–60 minutes.

**Approx vs exact distinct counts are surfaced separately.** `user_count_approx` uses Trino's `approx_distinct` (HLL, ~1.6% error, fast); `user_count` is exact (slow on large cohorts). Default to approx; switch to exact only when reconciling with finance or compliance reports.

## Setup

```bash
# 1. Configure
cp .env.example .env
# edit .env — fill in CUBEJS_DB_HOST, CUBEJS_DB_USER, CUBEJS_DB_PASS,
# CUBEJS_DB_PRESTO_CATALOG, CUBEJS_DB_SCHEMA for your Trino cluster.

# 2. Adjust schema for any column names that differ from the assumptions in
#    cube/model/cubes/active_daily.yml and recharge.yml — the mf_users.yml
#    is mapped exactly to the document you provided.

# 3. Spin up
docker compose up -d
docker compose logs -f cube_api    # watch for "API server is listening"

# 4. Verify
open http://localhost:4000          # Cube Playground (visual query builder)
```

## Test

```bash
# Smoke-test all 7 REST queries
bash examples/01_test_rest_api.sh

# SQL API (Postgres-compatible wire protocol)
psql -h localhost -p 15432 -U cube -d cube
# then paste queries from examples/02_test_sql_api.sql

# DSL → Cube compiler demo (the LLM/MCP integration shape)
pip install requests
python examples/03_segment_dsl_compiler.py
```

In the Playground, every query has an "SQL Query" tab — click it to see the exact Trino SQL Cube generated. This is the fastest way to sanity-check that pre-aggregations are matching (look for `cube_store.preagg_…` in the FROM clause) and that filters pushed down correctly.

## Adapting to your real schema

Schemas were verified against the live `game_integration.ballistar_vn` Trino catalog and the model now matches actual column names. If you point this at a different schema:

1. **`recharge.yml`** uses `etl_ingame_recharge` (raw transactions). Join key to mf_users is `account_id` (= `user_id`). Money is `charged_value` (VND).
2. **`active_daily.yml`** uses `std_ingame_user_active_daily`. Day-of values live under `ingame_last_active_*` prefixes (not bare `server_id`/`role_id`/etc.).
3. **`user_recharge_daily.yml`** uses `std_ingame_user_recharge_daily` (one row per user per recharge day). Prefer this over raw `etl_ingame_recharge` for per-user revenue timelines — ~2× faster.

`.env` Trino host/port/catalog/schema must point to a reachable cluster.

## 1-user 360 view — design + measured latency

The four entity-first views in `cube/model/views/user_360.yml` are what the LLM/MCP/BI tier should query for "show me everything about user X":

| View | Source | What it returns |
|---|---|---|
| `user_profile` | `mf_users` | 1 wide profile row |
| `user_activity_timeline` | `std_ingame_user_active_daily` | Day-by-day activity rows |
| `user_recharge_timeline` | `std_ingame_user_recharge_daily` | Day-by-day rolled-up revenue rows |
| `user_transactions` | `etl_ingame_recharge` | Per-transaction recharge events (optional) |

Each view answers a `user_id = ?` equality filter. The four queries are independent — issue them **in parallel** (see `examples/04_user_360_fanout.py`). Wall-clock then equals the slowest leg, not the sum.

**Measured end-to-end latency** (4-way fan-out, full 360 view, against `trino.gio.vng.vn`):

| Path | p50 wall-clock | Notes |
|---|---|---|
| Warm (Cube result cache hit) | **~190 ms** | ✅ Beats the 500 ms target with headroom |
| Cold (first ever lookup of a user) | **~4.5 s** | Bounded by Trino single-user query (~0.4 s × ~10× Cube pipeline overhead per leg) |

The cache TTL is set per-cube via `refresh_key`:
- `mf_users`: 1 h (daily ETL upstream)
- `std_ingame_user_active_daily`, `std_ingame_user_recharge_daily`: 30 min
- `etl_ingame_recharge`: 5 min

`CUBEJS_CONCURRENCY=8` (in `.env`) is required — the default of 2 serialises 4 parallel queries into two waves and roughly doubles cold-path latency.

**To get cold lookups under 500 ms too**, add `originalSql` pre-aggregations on the three bounded-size sources (`mf_users`, `std_ingame_user_recharge_daily`, `std_ingame_user_active_daily`). Those cache the source rows in Cube Store and serve single-user queries from there. Skipped for now — was disabled in the original model because partitioned rollups took >17 min to build first time; an unpartitioned `originalSql` cache is a different (smaller) build and worth revisiting when this goes to production.

Quick benchmark recipes:
- `examples/bench_360_users.sh` — cold + warm 360 across 4 users
- `examples/bench_trino_raw.sh` — same queries against Trino directly (no Cube), for floor-latency comparison
- `examples/check_cube_sql_speed.sh` — runs the exact SQL Cube emits, directly on Trino; confirms whether slowness is Cube vs Trino

## Production hardening checklist

When you're past POC and ready to deploy for real:

- Replace `CUBEJS_DEV_MODE=true` with proper JWT auth (`CUBEJS_JWK_URL` or RS256 keys); set `CUBEJS_API_SECRET` from a secret manager.
- Add `cube.py` (or `cube.js`) with `query_rewrite` for row-level security — e.g., per-team Trino user impersonation, country-based access, PII masking via `access_policies`.
- Split `cubestore_router` and N `cubestore_worker` replicas; mount `CUBESTORE_REMOTE_DIR` to S3 / GCS instead of a local volume.
- Run multiple `cube_api` replicas behind a load balancer; one dedicated `cube_refresh_worker` (`CUBEJS_REFRESH_WORKER=true`) for scheduled pre-agg builds.
- Enable `CUBEJS_ROLLUP_ONLY=true` once pre-aggs cover all production queries — this prevents accidental Trino scans for queries that should hit cache.
- Wire metrics: Cube exposes Prometheus-compatible endpoints; track `cube_query_duration_seconds`, pre-agg hit rate, refresh lag.
- Version the schema in git; CI: `cubejs validate` on every PR + smoke-test queries against staging Trino.

## Where this sits vs the design discussion

This implements the layers we discussed:

| Layer (concept)     | In Cube                                              |
| ------------------- | ---------------------------------------------------- |
| Entity & Sources    | `cubes:` with `sql_table` + `joins`                  |
| Attributes          | `dimensions:` (incl. `case` for classifications)     |
| Metrics             | `measures:` (incl. ratio measures and filtered ones) |
| Pre-agg / mat. hint | `pre_aggregations:` (rollup, partitioned)            |
| Segment DSL         | `segments:` + the Python compiler in examples/03     |
| Compiler            | Cube's built-in query planner (do not reinvent)      |
| API surface         | REST + GraphQL + SQL API (all built-in)              |

The `mf_users` materialization-hint advantage is preserved: queries that only need lifetime / 30d rolling metrics read directly from `mf_users` (one column scan), and Cube falls back to `active_daily`/`recharge` only when the time window doesn't match what's pre-computed in `mf_users`.
