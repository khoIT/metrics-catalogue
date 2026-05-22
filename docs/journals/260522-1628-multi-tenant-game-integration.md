# Multi-tenant routing for game_integration

**Date:** 2026-05-22 · **Author:** khoitn · **Audience:** future-me / next teammate
extending the Cube semantic layer beyond Ballistar.

Commit: `f6ec1e5 feat(cube): multi-tenant routing for game_integration`

---

## TL;DR

Single Cube deployment now serves four games (`ballistar`, `cfm`, `ptg`, `jus`)
out of the shared `game_integration` Trino catalog. JWT carries `{ userId, game }`;
`checkAuth` resolves `allowedGames` from a pluggable auth DB and rejects
cross-tenant access. `contextToAppId` + `driverFactory` + `scheduledRefreshContexts`
isolate compile cache, Trino schema, and pre-agg storage per game. No YAML
edits required — bare `sql_table` names resolve against the per-tenant
driver schema.

---

## Why Option A (single deployment, security-context routing)

Three architecture options were on the table:

| Option | Shape | When right |
|---|---|---|
| **A. Single deployment, multi-tenant via security context** | One Cube, JWT carries tenant, `driverFactory` swaps schema | Identical cube defs across games, same warehouse, RLS is on the roadmap |
| B. One deployment per game | 4× Cube, each locked to one schema via env | Per-game divergent cube defs, hard tenant isolation, separate release cadence |
| C. Single deployment, multiple dataSources | One Cube, cubes declare `dataSource: <game>` | Schemas live in **different DBs**, not just different schemas |

A wins for this codebase because:
- The four games share one Trino catalog → no cross-DB routing needed (rules out C).
- Cube definitions are identical across games (game_integration tables have
  the same shape per schema) → maintaining 4 forks is pure overhead (rules out B).
- The auth DB was already required for "who can see which game" → adding
  tenant routing on the same security-context pipeline costs nothing extra,
  and the same hook becomes the RLS attachment point later.

---

## Three locked-in trade-offs

User-confirmed before implementation:

1. **`allowedGames` source: auth DB lookup at checkAuth time, not a JWT claim.**
   Revoking access is one DB update; no token reissue. Cost is a per-request
   lookup. Mitigated by file-backed mtime cache in dev; production swap-in
   needs a real LRU/TTL cache (`TODO(prod)` in `cube/auth-db.js`).

2. **Pre-agg storage: shared Cube Store, 4× footprint accepted.**
   Each game gets its own orchestrator → pre-agg tables are namespaced via
   `contextToOrchestratorId` and never collide. Storage scales linearly with
   tenant count. If footprint becomes a problem later, switch to lazy on-demand
   pre-agg builds per game.

3. **Refresh worker: shared single worker iterating 4 tenant contexts.**
   `scheduledRefreshContexts` returns 4 synthetic security contexts, one per
   game. Worker runs in-process with the API on the single-node POC. Split
   into a dedicated `cube_refresh` service when event-loop contention shows up
   (recipe in `.env.example`).

---

## Non-obvious wiring decisions

### File layout: `cube/cube.js`, not `cube.js` at repo root

First draft put `cube.js` at the repo root next to `docker-compose.yml`,
with `auth-db.js` under `cube/`. The relative require (`./auth-db`) broke
because Cube auto-loads `/cube/conf/cube.js` inside the container — they
needed to be siblings *both* on host and in container.

Fix: put everything under `cube/` and broaden the docker-compose mount from
`./cube/model:/cube/conf/model:ro` to `./cube:/cube/conf:ro`. Now `cube.js`,
`auth-db.js`, `auth-users.json`, and `model/` all sit at `/cube/conf/`
inside the container, mirroring the host layout exactly.

### YAMLs stay untouched

The four cube definitions and the user_360 view use bare `sql_table` names
(`mf_users`, `std_ingame_user_active_daily`, etc.). Cube resolves these
against the driver's configured schema. Returning a fresh driver per request
with `schema: GAME_SCHEMA[game]` makes the swap invisible to the YAML
layer. Zero per-game YAML forks. If a game ever needs a divergent cube
definition, layer Option C (per-game `dataSource`) on top — but that day
is not today.

### Refresh-worker contexts need a sentinel role

The refresh worker has no JWT. Its security contexts are hand-built in
`scheduledRefreshContexts` and tagged with `roles: ['__refresh__']`. This
matters when `queryRewrite` grows real row-level rules — system refresh
calls must bypass user-scoped filters, otherwise pre-aggs only contain
the rows that the "first user" was allowed to see. Cheaper to bake the
sentinel in now than retrofit it later.

### `CUBEJS_DB_SCHEMA` is not just removed — it must stay unset

Leaving `CUBEJS_DB_SCHEMA=ballistar_vn` in `.env` would silently shadow the
per-tenant schema from `driverFactory`. The env var precedence is non-obvious
from Cube's docs. Added an explicit comment in `.env.example` noting that
schema is resolved per-tenant in `cube.js` and the env line is intentionally
omitted.

### Dev mode must be OFF

`CUBEJS_DEV_MODE=true` bypasses `checkAuth` entirely — tenant routing never
runs and every request hits whatever the default driver returns. Flipped to
`false` with a comment explaining why. The Playground still works, but you
have to paste a JWT into the auth field (use `examples/00_mint_jwt.sh`).

---

## RLS readiness

The same `securityContext` that drives routing today is the substrate RLS
will hook into tomorrow. `cube.js` ships with a no-op `queryRewrite` and a
commented-out example showing the canonical pattern (filter `recharge.user_id`
to `securityContext.userId` for non-admins). Adding real rules is now a
single-file change with no rewiring.

Two cleaner extension paths exist when more depth is needed:

- **`accessPolicy` blocks per cube/view** for per-role member visibility
  (Cube's newer RLS primitive — gated by `roles` already present in the
  security context).
- **Per-tenant Trino impersonation**: extend `driverFactory` to set
  `user: securityContext.userId` so Trino's own row filters / column masks
  apply downstream.

---

## What's untouched but worth flagging

- `cube-entrypoint-patched.sh` still strips `SET SESSION query_max_run_time`
  (the Trino role lacks the privilege). Multi-tenancy doesn't change that.
- The 11-dimension UTC timezone fix from the previous journal still applies —
  game schemas in CFM/PTG/JUS will need the same `from_iso8601_timestamp(...)`
  pattern in any new cubes that ship.
- `mf_users` pre-agg in `active_daily.yml` is the only one defined; the
  refresh worker iterates 4 tenants × 1 pre-agg today. Adding pre-aggs is
  a multiplier — budget storage accordingly.

---

## Verification

- `node --check cube/cube.js` — clean
- `node --check cube/auth-db.js` — clean
- `docker compose config -q` — clean
- `bash -n examples/{00_mint_jwt,05_test_multi_tenant}.sh` — clean
- `examples/05_test_multi_tenant.sh` exercises all four games + one
  cross-game deny path; ready to run once Trino is reachable from the
  container and `cube/auth-users.json` is seeded.

---

## Follow-ups (not in this commit)

- Real DB-backed `getUserAccess` (Postgres or internal auth API). Public
  signature stays the same; `cube/auth-db.js` is the only file that changes.
- TTL/LRU cache around the auth lookup once it hits a real DB.
- First concrete `queryRewrite` rule when the first RLS requirement lands.
- Move refresh worker into its own compose service if API event-loop
  pressure shows up.
- CFM / PTG / JUS cube schemas may diverge from Ballistar's column names.
  Plan B if so: per-game cube definitions via Cube's multi-root model and a
  per-tenant `CUBEJS_SCHEMA_PATH` override in `driverFactory`-adjacent config.
