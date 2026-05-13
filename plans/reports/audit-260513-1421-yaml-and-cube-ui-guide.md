# Cube YAML audit + UI exploration guide

**Date:** 2026-05-13 | **Schema:** `game_integration.ballistar_vn` | **Cube ver:** 1.6.46

## 1. YAML audit results

### Fixes applied (this session)

| File | Lines | Change | Reason |
|---|---|---|---|
| `mf_users.yml`, `active_daily.yml`, `recharge.yml`, `user_recharge_daily.yml` | `sql_table:` | dropped `ballistar_vn.` prefix | schema agnostic — driven by `CUBEJS_DB_SCHEMA` |
| `mf_users.yml` (7), `active_daily.yml` (2), `recharge.yml` (1), `user_recharge_daily.yml` (1) | 11 time dimensions | `CAST(col AS TIMESTAMP)` → `from_iso8601_timestamp(CAST(col AS VARCHAR) || 'T00:00:00Z')` | session-TZ independence (Trino server defaults to `Asia/Ho_Chi_Minh`, was shifting dates -7h) |

### YAML is consistent

- All 4 cubes parse cleanly (`/cubejs-api/v1/meta` returns 4 cubes + 7 views)
- `recharge.recharge_time` (already `timestamp with time zone`) correctly left untouched
- `log_month` string columns (`varchar`) left as `type: string`
- View `includes:` references match cube member names

### Validated end-to-end (cube → Trino → Cube ⇒ value matches direct Trino)

| Cube / View | Probe | Result | Matches Trino |
|---|---|---|---|
| `mf_users.user_count_approx` | filter-less | 492,678 | ✅ |
| `active_daily.dau` | date=2026-05-06 | 16,278 | ✅ |
| `recharge.revenue_vnd` | date=2026-05-06 | 474,337,000 VND | ✅ |
| `user_recharge_daily.revenue_vnd_total` | date=2026-05-06 | 474,337,000 VND | ✅ |
| `user_audience` × `payer_tier` | filter-less | 4 rows; non_payer=465,713 | ✅ |
| `activity_metrics.dau` | daily series 5/1–5/6 | 6 rows; 5/1=18,073 | ✅ |
| `revenue_metrics.revenue_vnd` | daily series 5/1–5/6 | 6 rows; 5/1=577,089,000 | ✅ |
| `user_profile` (SQL API) | `user_id=3368…` | non_payer, ltv=0 | ✅ |
| `user_activity_timeline` (SQL API) | `user_id=3368…` | 0 rows (user never active — expected) | ✅ |

### Not directly probed but architecturally validated

- `user_recharge_timeline` — thin wrapper over `user_recharge_daily` (verified)
- `user_transactions` — thin wrapper over `recharge` (verified)
- Both will return 0 rows for a non-payer (expected) and rows for paying users

## 2. Infrastructure adjustments still needed

| Item | Status | Action |
|---|---|---|
| `cubejs/cubestore:latest` (amd64) crashes under QEMU on Apple Silicon | swapped to `cubejs/cubestore:arm64v8` | done in `docker-compose.yml` |
| `cube_api` native arm64 has broken cubestore-driver (queue stalls indefinitely) | pinned to `platform: linux/amd64` (under Rosetta) | done in `docker-compose.yml` |
| Cube Store env was incomplete (port 9999 never bound) | added `CUBESTORE_PORT=9999`, `CUBESTORE_META_PORT=9999` | done |
| `CUBEJS_DB_SSL=true` (Trino HTTPS on :8080) | done | — |
| `CUBEJS_DB_PRESTO_CATALOG=game_integration` (was `hive`) + alias `CUBEJS_DB_CATALOG=game_integration` | done | — |
| `CUBEJS_CUBESTORE_HOST=cubestore` (was `cubestore_router`) | done | — |
| `TZ=UTC` on cube_api | added (helpful but YAML fix is what actually drove correctness) | — |

## 3. How to best explore the Cube UI given these data shapes

**Playground URL:** http://localhost:4000

### Cube Playground basics

- **Cubes tab** lists raw cubes: `mf_users`, `active_daily`, `recharge`, `user_recharge_daily`. Use only for ad-hoc model exploration.
- **Views tab** is what BI / LLM / app code should use. 7 views are split into two consumption shapes:
  - **4 user-level views** (1 user at a time, sub-second): `user_profile`, `user_activity_timeline`, `user_recharge_timeline`, `user_transactions`
  - **3 metric views** (aggregations across many users): `user_audience`, `revenue_metrics`, `activity_metrics`
- Every query result has a **"Generated SQL"** tab — click it to inspect the exact Trino SQL Cube emits. Look for `cube_store.preagg_…` in the FROM clause to confirm a pre-aggregation hit.

### Recommended exploration paths

#### Path A — Single-user 360 (read-the-detail)

For any view named `user_*`, **always add a `user_id = …` equals filter**. Without it Cube runs a full table scan of 492K rows.

1. Pick a real user_id (Trino: `SELECT user_id FROM ballistar_vn.mf_users LIMIT 1`)
2. Hit each of the 4 user_* views with that ID — they're designed to be issued in parallel (~190 ms warm, ~4.5 s cold) and form the 360 panel:
   - `user_profile` — wide row, identity + LTV + classifications
   - `user_activity_timeline` — daily activity rows
   - `user_recharge_timeline` — daily revenue rolled up
   - `user_transactions` — per-transaction grain
3. See `examples/04_user_360_fanout.py` for the parallel-fanout shape

#### Path B — Cohort / segment analytics (slice-and-dice)

Use `user_audience` view. It exposes mf_users with both dimensions (country, payer_tier, lifecycle_stage, install_month…) and measures (user_count, paying_rate, ltv_total_vnd, whales_count…).

Useful first queries to try:
- Group by `payer_tier` → measure `user_count_approx` → shows the whale/dolphin/minnow/non_payer mix (confirmed: 465,713 non_payers)
- Group by `country` + `payer_tier` → filter `is_paying_user = true` → revenue concentration by country
- Apply segment `whales` (predefined) → measure `ltv_total_vnd` → total whale spend
- Apply segments `vn_users + at_risk_paying` → measure `user_count_approx` → "VN whales drifting away"

The pre-defined **segments** (`vn_users`, `whales`, `at_risk_paying`, `paid_install`, etc.) collapse common audience filters into one click. Try toggling them before adding manual filters.

#### Path C — Time-series dashboards

Use `activity_metrics` (DAU/MAU) or `revenue_metrics` (recharge).

1. Add the time dimension (`log_date` or `recharge_date`) with **granularity = day** (or month/week)
2. Pick a date range — 7-day, 30-day window with the `last_7d` / `last_30d` segments
3. Add a dimension like `country_code`, `os_platform`, or `payment_channel` to slice the metric
4. Watch **MAU vs MAU_prev_month** for engagement health
5. `revenue_metrics.arppu_vnd` = revenue / paying_users — gives revenue health independent of paying user growth

#### Path D — Inspect schema model

In the Playground:
- Click ℹ next to any cube/view to see its description
- "Show Members" panel surfaces all dimensions & measures with descriptions
- The "SQL Query" panel after Run shows whether your filter pushed down properly

### Quick gotchas to flag in the UI

1. **`user_count_approx` vs `user_count`** — always default to approx (HLL, ~1.6% error, ms-fast). Switch to exact only when reconciling with finance/compliance.
2. **`mf_users` rolling 30d metrics are pre-computed** — `ltv_30d_vnd`, `txn_count_30d` are read as single columns. Don't recompute from `recharge` unless you need a window other than 30d.
3. **`payer_tier` and `lifecycle_stage`** are `case` dimensions — usable as both group-by AND filter, but they trigger a `CASE WHEN …` in SQL (slightly more expensive than a plain column).
4. **Date filters with `dateRange`** now work correctly under any session timezone (YAML fix in §1). If you see 0 rows on a non-empty day, click "Generated SQL" and check the WHERE — should contain `from_iso8601_timestamp(…)` not `CAST(… AS TIMESTAMP)`.
5. **First cold query takes ~30–60 s** — Cube boots cubestore metadata + driver pool. Subsequent queries on same key are <1 s (result cache).

### When the Playground is slow

- Filter-less `user_*` view queries scan 492K rows — **always** filter by `user_id`
- Big `user_audience` cross-tabulations (5+ dimensions) — start with 2 dimensions, add one at a time
- If a query gets "stuck" in Continue wait: open another query tab and run a tiny aggregate against the same cube to warm refresh keys

## 4. Unresolved

- **Cube Store flakiness**: After ~10 minutes of mixed-load probing, refresh_key resolution against cubestore intermittently stalls (queue saturates, "Corrupted message" log spam). Restart `cube_api` to clear. Not a model issue — appears to be cubestore arm64v8 ↔ amd64 cube_api edge case under emulation. The colleague's Windows setup avoids this since both containers run native amd64.
- **Hardcoded Trino credentials** in `examples/trino_q.{sh,py}` (`gds_da` / `HSayxxgeMPtW2DnP4KXH`) — should move to env and rotate.
- **`mau_prev_month` filter** in `active_daily.yml` line 129 uses bare `log_date` comparison — works because both sides become DATE; verify if you change the dimension expression.
- **Cubestore on-disk metastore** still has stale state from earlier QEMU crashes; was reset once this session. If queries stop working after long idle, `docker compose down && docker volume rm cube-dev_cubestore_data && docker compose up -d`.
