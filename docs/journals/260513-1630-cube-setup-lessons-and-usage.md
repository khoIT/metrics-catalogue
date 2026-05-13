# Cube setup — lessons & usage primer

**Date:** 2026-05-13 · **Author:** khoitn · **Audience:** future-me / future-teammate reopening this repo in 3 months

Companion doc: `260513-1629-cube-semantic-layer-foundation.md` covers the system anatomy. This one is the *experiential* notes — what bit us, what's not in the README, how to actually drive it.

---

## TL;DR — the 6 hours of pain in 6 bullets

1. **Apple Silicon: keep cube_api amd64-under-Rosetta + cubestore arm64v8.** Native arm64 cube_api has a broken cubestore-driver. amd64 cubestore crashes silently under QEMU.
2. **Trino server defaults its session to `Asia/Ho_Chi_Minh`.** Cube driver does NOT propagate UTC. Filtered queries return `0` silently. Fix is in YAML, not env.
3. **`.env` had 4 latent bugs the README doesn't catch.** SSL flag wrong, catalog wrong, cubestore hostname mismatched, missing alias env.
4. **`docker compose restart` does NOT reload `.env`.** Need `up -d` (recreate).
5. **VPN routes don't propagate from macOS into the colima VM.** Container can resolve `internal-host.vng.vn` to `10.x.x.x` but can't route to it. Host curl works, container hangs.
6. **Cube Store flakes after ~10 min of mixed-load probing.** Restart cube_api clears it.

---

## Lesson 1 — The Apple Silicon container trap (counterintuitive)

`cubejs/cubestore:latest` only publishes `linux/amd64`. On M-series Mac with colima:
- Pinning `platform: linux/amd64` and running under QEMU → cubestored crashes with `Illegal instruction`, drops a core file (`qemu_cubestored_*.core`), and the process exits silently. From outside it looks like cubestore is "up" (container alive) but it's not. Symptom is REST queries stuck in `"error":"Continue wait"` forever, because Cube API waits for `refresh_key` evaluation against a dead cubestore.
- Switching colima to `vz` + Rosetta (`colima start --vm-type vz --vz-rosetta`) didn't help — Rosetta also failed (likely AVX-512 not translated).
- **Fix: `image: cubejs/cubestore:arm64v8`** — community arm64 build. Native, no emulation, boots clean, binds port 9999 properly.

But — and this is the counterintuitive part — for **cube_api**, the same logic does NOT apply:
- `cubejs/cube:latest` has both amd64 and arm64 manifests
- Running the **native arm64** cube_api with arm64 cubestore caused the cubestore-driver queue to stall indefinitely. Queries never reached Trino. queueId kept incrementing past 100, refresh_key never resolved.
- Reverting cube_api to `platform: linux/amd64` (under Rosetta) **immediately fixed it**.

So the working combo on Apple Silicon is **mixed arch**: cube_api=amd64 (Rosetta), cubestore=arm64v8 (native).

Colleague's Windows didn't hit either issue because both containers ran native amd64. Their "it works on my machine" is real; ours is real too; the combo is just genuinely fragile on macOS arm64.

---

## Lesson 2 — The Trino timezone trap (worst rabbit hole of the day)

Burned ~90 min on this one. Symptoms:
- DAU query for `2026-05-06` returns **0**
- Same SQL via `trino_q.py` also returns 0
- Same SQL with `X-Trino-Time-Zone: UTC` returns **16,278** ← the truth

Root cause unraveled:
1. Trino server's default session timezone is `Asia/Ho_Chi_Minh` (confirmed via `SELECT current_timezone()`)
2. The YAML expression `CAST({CUBE}.log_date AS TIMESTAMP)` produces a `timestamp(0)` *without* time zone
3. Cube generates the WHERE clause as `from_iso8601_timestamp('2026-05-06T00:00:00.000Z')` — a `timestamp(3) with time zone`
4. Trino implicit-casts the no-TZ side using session TZ → `DATE '2026-05-06'` becomes `2026-05-06 00:00 +07` = **`2026-05-05 17:00 UTC`**
5. That instant is **outside** the filter range `[2026-05-06 00:00 UTC, 2026-05-06 23:59 UTC]` → row excluded → DAU = 0

What didn't work:
- Setting `TZ=UTC` in cube container — TZ doesn't propagate to the prestodb-driver's `X-Trino-Time-Zone` header
- Setting `CUBEJS_DB_TIMEZONE=UTC` — no such env honored by trino driver
- Wrapping cast with `AT TIME ZONE 'UTC'` — Trino interprets the naive timestamp in session TZ *first*, then relabels (same wrong instant, different label). Still 0.

What worked: rewrite the dimension expression to **construct a TZ-aware timestamp literally at UTC midnight**:

```yaml
sql: "from_iso8601_timestamp(CAST({CUBE}.log_date AS VARCHAR) || 'T00:00:00Z')"
```

Applied across **11 time dimensions** in `mf_users.yml` (7), `active_daily.yml` (2), `recharge.yml` (1), `user_recharge_daily.yml` (1). All date filters now correct regardless of session timezone.

Colleague's Windows mystery: presumably Docker Desktop on Windows propagates `TZ=UTC` into the cube container in a way that the prestodb-driver picks up. Or their Trino default is UTC. Didn't dig further. The YAML fix makes us TZ-independent, which is the right invariant anyway.

---

## Lesson 3 — Four `.env` bugs the README doesn't mention

The `.env.example` has reasonable defaults *for some other cluster*. For `gio-gds-trino.vnggames.net`:

| Field | `.env.example` default | Actual correct value | Symptom if wrong |
|---|---|---|---|
| `CUBEJS_DB_SSL` | `false` | **`true`** | Cube logs `Error: request to http://...:8080/v1/info failed, reason: connect ECONNREFUSED` (cluster requires HTTPS on :8080) |
| `CUBEJS_DB_PRESTO_CATALOG` | `hive` | **`game_integration`** | Trino returns `SCHEMA_NOT_FOUND` (ballistar_vn exists under game_integration, not hive) |
| `CUBEJS_DB_CATALOG` | (missing) | **`game_integration`** | newer trino driver uses `_CATALOG` name; safer to set both aliases |
| `CUBEJS_CUBESTORE_HOST` | `cubestore_router` | **`cubestore`** | DNS lookup fails (`getent hosts cubestore_router` → ENOTFOUND). Compose service is named just `cubestore` |

Two of these (SSL and catalog) symptoms surfaced as just "Continue wait" forever — no error returned to the client. Debugging required either Trino-side query log inspection (`system.runtime.queries`) or bumping Cube to `CUBEJS_LOG_LEVEL=trace`.

---

## Lesson 4 — Hard-coded schema in YAML defeats reusability

Original `cube/model/cubes/*.yml` had `sql_table: ballistar_vn.mf_users`. That means changing games requires editing 4 YAML files.

Drop the prefix: `sql_table: mf_users`. The `CUBEJS_DB_SCHEMA` env then drives the choice. Game swap is now a 1-line `.env` change.

(Verified this worked end-to-end when we briefly pointed at `cfm_vn` mid-session before reverting to `ballistar_vn`.)

---

## Lesson 5 — Docker/VPN quirks on macOS

**`docker compose restart` does NOT reload `.env`.** It signals SIGTERM and brings the same container back with cached env. To pick up `.env` changes use `docker compose up -d` (or `up -d --force-recreate`). Wasted ~30 min on this; only realized when `docker exec ballistar_cube_api env | grep CUBEJS_DB_SSL` still showed `false` after I had flipped it to `true` and "restarted".

**VPN routes don't reach the container.** Host can curl `https://gio-gds-trino.vnggames.net:8080/v1/info` and get 200 OK; container resolves the same DNS to the same internal IP (`10.164.54.88`) but TCP connection times out. The macOS VPN client (`utun4`) installs routes only in the host network namespace; colima's VM and Docker bridges are downstream of that. If host curl works but container doesn't, you're hitting this.

---

## Lesson 6 — Cube Store flakes under sustained load

After ~10 min of running multiple parallel REST probes, the cubestore queue saturates and refresh_key resolution stalls indefinitely. Symptom: Cube logs show endless `"queuePrefix": "SQL_QUERY_EXT_STANDALONE"` with incrementing queueIds (saw it hit 100+), zero queries reaching Trino, no error messages.

Cubestore log shows periodic `Network error: Corrupted message received. Please check your worker and meta connection environment variables.` — appears to be benign noise from gossip-for-missing-peers in single-node mode, but the saturation it correlates with is real.

Workaround: `docker compose restart cube_api` clears the queue. Don't run many concurrent probe batches.

---

## Usage primer

### Bring up the stack

```bash
cd /Users/lap16299/Documents/code/cube-dev
docker compose up -d
docker compose logs -f cube_api    # wait for "🚀 Cube API server (1.6.46) is listening on 4000"
```

### Four ways to query

| Surface | URL | Best for |
|---|---|---|
| Playground | http://localhost:4000 | Interactive exploration, Generated SQL inspection |
| REST | `POST http://localhost:4000/cubejs-api/v1/load` | App/LLM integration |
| GraphQL | `POST http://localhost:4000/cubejs-api/graphql` | Type-safe clients |
| SQL API | `psql -h localhost -p 15432 -U cube -d cube` (password: `cube`) | BI tools, sometimes more responsive when REST hangs |

### Playground tips that save time

- **Use Views, not raw Cubes.** Views are the consumption surface. Raw cubes are model-internal.
- **The 4 `user_*` views REQUIRE `user_id = <id>` equals filter** — without it they full-scan 492K rows
- **Click "Generated SQL"** after Run to verify filter pushdown and confirm pre-agg hits (`cube_store.preagg_…` in FROM)
- **First query is cold ~30–60 s**; subsequent on same key are sub-second (result cache)
- **Default to `*_approx` measures** (HLL, ~1.6% error, ms-fast). Switch to exact only for finance reconciliation.

### Three exploration paths

| Goal | View | Key tip |
|---|---|---|
| One user 360 | `user_profile`, `user_activity_timeline`, `user_recharge_timeline`, `user_transactions` | Filter `user_id = …`, issue all 4 in parallel (~190 ms warm, ~4.5 s cold) |
| Cohort / segment slice | `user_audience` | Try predefined segments (`whales`, `vn_users`, `at_risk_paying`, `paid_install`) before manual filters |
| DAU/MAU/revenue dashboards | `activity_metrics`, `revenue_metrics` | Add time dim with granularity=day, slice by `country_code`/`os_platform`/`payment_channel` |

### Verified end-to-end smoke values (2026-05-13 snapshot)

These match direct Trino — useful as canary checks after future changes:

- `mf_users.user_count_approx` = **492,678** users
- `active_daily.dau` (2026-05-06) = **16,278**
- `recharge.revenue_vnd` (2026-05-06) = **474,337,000 VND**
- `user_recharge_daily.revenue_vnd_total` (2026-05-06) = **474,337,000 VND** (cross-check matches above)
- `user_audience` × `payer_tier` → non_payer ≈ **465,713**
- `activity_metrics` daily series 5/1–5/6 → 5/1 DAU = **18,073**
- `revenue_metrics` daily series 5/1–5/6 → 5/1 revenue = **577,089,000 VND**

### Latest data is stale by ~7 days

As of 2026-05-13, max `log_date` in `std_ingame_user_active_daily` = **2026-05-06**. Don't query "yesterday" expecting fresh — the upstream ETL lags.

---

## Unresolved

- **Cubestore flake under sustained load** — symptom clears with `docker compose restart cube_api` but root cause unknown. Possibly arm64 cubestore ↔ amd64 cube_api protocol edge case. Worth filing upstream if it persists in production.
- **Hard-coded Trino credentials** in `examples/trino_q.{sh,py}` (`gds_da` / `HSayxxgeMPtW2DnP4KXH`) — should be env vars; current creds should be rotated since they're in git history.
- **`mau_prev_month` filter** in `active_daily.yml` line 129 uses bare `log_date` comparison (no `from_iso8601_timestamp` wrap). Works for now because both sides are DATE; will silently break if the dimension expression changes.
- **Windows colleague's setup mystery** — why does identical YAML work there without the TZ fix? Suspect Docker Desktop on Windows propagates `TZ=UTC` into the prestodb-driver session header. Not chased to ground.
- **VPN reachability stability** — host VPN dropped once mid-session and recovered when reconnected. For autonomous CI/cron use of the playground, need a more stable network path (public Trino endpoint, or run on a server inside the corp network).
