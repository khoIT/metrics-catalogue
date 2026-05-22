# Multi-tenant Cube for game_integration (ballistar, cfm, ptg, jus)

## Goal
Extend the single-game (`ballistar_vn`) Cube deployment into a multi-tenant
deployment that serves 4 games from the same `game_integration` Trino catalog,
with JWT-based auth and authDB-driven access control as the foundation for
later RLS rules.

## Architecture (Option A — single deployment, security-context routing)
- One Cube API. Per-request JWT carries `{ userId, game }`.
- `checkAuth` verifies signature → looks up `allowedGames` from authDB → rejects if
  requested `game` ∉ allowedGames.
- `contextToAppId` / `contextToOrchestratorId` namespace by game → isolated
  compile cache + pre-agg storage per tenant.
- `driverFactory` returns a Trino driver with `schema = GAME_SCHEMA[game]`.
  Existing YAMLs use bare `sql_table`, so no schema edits needed.
- `scheduledRefreshContexts` enumerates all 4 games → refresh worker ticks
  per-tenant pre-aggs.
- `queryRewrite` left as a no-op extension point for future row/field RLS.

## Trade-offs locked in
- **allowedGames source:** authDB lookup at checkAuth time (not JWT claim).
- **Pre-agg storage:** shared CubeStore, 4× footprint accepted.
- **Refresh worker:** shared single worker, iterates 4 tenant contexts.

## Files touched
- **New:** `cube.js` (root config — multi-tenant hooks)
- **New:** `cube/auth-db.js` (authDB lookup interface; dev impl reads JSON)
- **New:** `cube/auth-users.example.json` (dev seed for 4 games × sample users)
- **New:** `examples/00_mint_jwt.sh` (dev JWT minter helper)
- **New:** `examples/05_test_multi_tenant.sh` (per-game smoke test)
- **Update:** `.env.example` (remove `CUBEJS_DB_SCHEMA`, document JWT shape)
- **Update:** `docker-compose.yml` (mount `cube.js` + `auth-db.js` + users JSON; enable refresh worker)
- **Update:** `README.md` (multi-tenant section, JWT shape, dev workflow)
- **Untouched:** `cube/model/cubes/*.yml`, `cube/model/views/*.yml`

## Phases
1. [phase-01](./phase-01-multi-tenant-cube-config.md) — Write `cube.js` + `auth-db.js` + seed JSON.
2. [phase-02](./phase-02-env-and-compose-updates.md) — Env + docker-compose updates.
3. [phase-03](./phase-03-smoke-test-and-docs.md) — Smoke test + README.

## Success criteria
- 4 JWTs (one per game) each return data scoped to their schema.
- JWT for `ptg` requesting `cfm` data → 403.
- Refresh worker logs show context iteration for all 4 games.
- Existing single-tenant ballistar workflow still functions (with a JWT scoped
  to `ballistar`).

## Out of scope
- Real authDB driver (Postgres/MySQL connection) — dev impl uses JSON file,
  prod swap-in documented in `auth-db.js`.
- Per-user / per-role row filters in `queryRewrite` — extension point only.
- K8s manifests — this repo is a docker-compose POC.
