# Phase 02 — Env and docker-compose updates

## Context links
- Plan overview: [plan.md](./plan.md)
- Phase 01 (cube.js): [phase-01-multi-tenant-cube-config.md](./phase-01-multi-tenant-cube-config.md)

## Overview
- **Priority:** P0
- **Status:** pending
- Wire the new `cube.js` / `auth-db.js` / users JSON into the container, drop
  the now-obsolete `CUBEJS_DB_SCHEMA`, and enable the shared refresh worker.

## Key insights
- `cube.js` must mount at `/cube/conf/cube.js` for Cube to auto-load it.
- Auth lookup module + users JSON live under `/cube/conf/` alongside `model/`.
- `CUBEJS_DB_SCHEMA` becomes per-tenant in `driverFactory`. Leaving it in the
  env file would mislead operators (it has no effect once `driverFactory`
  returns a `schema`).
- `CUBEJS_DEV_MODE=true` bypasses `checkAuth` → must be `false` for the
  multi-tenant flow to be exercised.

## Requirements
**Functional**
- All 3 new files mounted read-only into the API container.
- Refresh worker enabled and shares the same `cube.js` (single-process by default).
- A valid JWT (any game) reaches the Cube API and gets data from the right schema.

**Non-functional**
- Backwards compatibility: a developer with a `ballistar`-scoped JWT must
  still get identical data to the pre-change setup.

## Architecture
No service topology change — same `cube_api` + `cubestore` services. Only
mounts + env vars change.

## Related code files
**Modify**
- `.env.example`
- `docker-compose.yml`

**Untouched**
- `cube-entrypoint-patched.sh` (still needed for the Trino SET-SESSION patch)

## Implementation steps
1. `.env.example`:
   - Set `CUBEJS_DEV_MODE=false` (with comment explaining why).
   - Remove `CUBEJS_DB_SCHEMA=ballistar_vn` (note in comment that it's
     resolved per-tenant in `cube.js`).
   - Set `CUBEJS_REFRESH_WORKER=true` and update the surrounding comment block
     (the old comment says "keep disabled" — replace with "enabled for
     multi-tenant scheduled refresh; iterates all games in `cube.js`").
   - Add `AUTH_USERS_FILE=/cube/conf/auth-users.json` with a comment pointing
     to `auth-users.example.json`.
   - Add a `# JWT shape` block documenting expected claims:
     `{ userId, game, iat }`.
2. `docker-compose.yml`:
   - Add volume mounts to `cube_api.volumes`:
     - `./cube.js:/cube/conf/cube.js:ro`
     - `./cube/auth-db.js:/cube/conf/auth-db.js:ro`
     - `./cube/auth-users.json:/cube/conf/auth-users.json:ro`
   - No service split — single API process also runs the refresh worker
     in-process (matches existing single-node POC posture).

## Todo list
- [ ] `.env.example` updated (dev mode off, schema removed, worker on, AUTH_USERS_FILE added, JWT-shape comment)
- [ ] `docker-compose.yml` updated (3 new mounts)
- [ ] `docker compose config` parses without error

## Success criteria
- `docker compose config -q` returns 0.
- `grep CUBEJS_DB_SCHEMA .env.example` returns no match.
- `grep -E '(cube\.js|auth-db\.js|auth-users\.json)' docker-compose.yml` shows 3 mounts.

## Risk assessment
- **Risk:** Operators who copy `.env.example` to `.env` lose their previous
  `ballistar_vn` setting. **Mitigation:** README upgrade note in phase 03.
- **Risk:** Refresh worker in-process with API may pressure event loop.
  **Mitigation:** comment in `.env.example` shows how to split into a
  dedicated worker service if/when needed.

## Security considerations
- `auth-users.json` (the real one, not `.example`) added to `.gitignore` to
  prevent accidental commit of access-control data.

## Next steps
- Phase 03 (smoke test) validates end-to-end after this phase lands.
