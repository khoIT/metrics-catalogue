# Phase 01 — Multi-tenant Cube config

## Context links
- Plan overview: [plan.md](./plan.md)
- Existing model: `cube/model/cubes/*.yml`, `cube/model/views/user_360.yml`
- Existing env: `.env.example`

## Overview
- **Priority:** P0 (foundation)
- **Status:** in-progress
- Add the three new JS files that turn the env-only Cube setup into a
  multi-tenant deployment routed by JWT security context.

## Key insights
- Cube YAMLs use bare `sql_table` → tenant schema swap happens entirely via
  the driver's `schema` config. Zero YAML edits.
- Cube already accepts a root-level `cube.js`; we just need to add one and
  Cube will pick it up. No image change.
- `checkAuth` runs **before** `contextToAppId`/`driverFactory`, so it can
  fully populate `securityContext` from JWT + authDB.

## Requirements
**Functional**
- Verify HS256 JWT signed with `CUBEJS_API_SECRET`.
- Reject if `game` claim missing, unknown, or not in user's `allowedGames`.
- Route each tenant to its Trino schema (`ballistar_vn` / `cfm_vn` / `ptg` / `jus_vn`).
- Isolate compile cache + pre-agg storage per tenant.

**Non-functional**
- authDB lookup interface must be one-file swappable (dev JSON → prod DB).
- No new npm deps beyond `jsonwebtoken` (already used in examples).

## Architecture

```
JWT (Authorization header)
   │
   ▼
checkAuth ──► jwt.verify(secret) ──► getUserAccess(userId) [authDB]
   │                                          │
   │                                          ▼
   │                                  { allowedGames, roles }
   │
   ▼
securityContext = { userId, game, allowedGames, roles }
   │
   ├──► contextToAppId          → "cube_<game>"      (compile cache key)
   ├──► contextToOrchestratorId → "orch_<game>"      (pre-agg namespace)
   ├──► driverFactory           → Trino { schema: GAME_SCHEMA[game] }
   └──► queryRewrite            → (no-op for now; RLS extension point)
```

## Related code files
**Create**
- `cube.js` (~80 LOC)
- `cube/auth-db.js` (~40 LOC)
- `cube/auth-users.example.json` (~30 LOC, dev seed)

**Modify** — none in this phase

## Implementation steps
1. Define `GAME_SCHEMA` map (4 games → schema names) in `cube.js`.
2. Implement `checkAuth(req, auth)`: jwt.verify → authDB lookup → enforce
   `game ∈ allowedGames` → attach `securityContext`.
3. Implement `contextToAppId` and `contextToOrchestratorId` from
   `securityContext.game`.
4. Implement `driverFactory({ securityContext })` returning Trino config with
   per-tenant `schema`.
5. Implement `scheduledRefreshContexts` returning 4 contexts (one per game)
   tagged with a synthetic `__refresh__` role so they bypass RLS later.
6. Add a stub `queryRewrite` that returns the query unchanged with a comment
   block describing the RLS extension pattern.
7. Implement `cube/auth-db.js` exporting `getUserAccess(userId)` backed by a
   JSON file at `AUTH_USERS_FILE` (default `/cube/conf/auth-users.json`).
   Include a `TODO` block sketching the production DB query.
8. Write `cube/auth-users.example.json` with 5–6 sample users covering:
   - one user per game (single-game access)
   - one cross-game admin (all 4)
   - one user with empty allowedGames (negative-path test)

## Success criteria
- `cube.js` syntactically loads (`node -e "require('./cube.js')"` no throw).
- `auth-db.js` exports `getUserAccess`.
- No reference to plan artifacts in code comments.

## Risk assessment
- **Risk:** `checkAuth` runs per-request → authDB call per request. **Mitigation:**
  document a TTL-cache TODO in `auth-db.js`. For dev JSON impl, parse cost is negligible.
- **Risk:** Cube YAMLs may reference `CUBEJS_DB_SCHEMA` somewhere we missed.
  **Mitigation:** grep all YAML before declaring done; per Explore report, none do.
- **Risk:** Refresh worker contexts lack a JWT-derived `game` — must be hand-built.
  **Mitigation:** `scheduledRefreshContexts` constructs the context object directly.

## Security considerations
- `CUBEJS_API_SECRET` must be ≥32 chars in prod (HS256). Already documented.
- `auth-users.json` should NOT be committed in real form — only `.example.json`.
- `queryRewrite` left as no-op; real RLS rules added when authDB schema lands.

## Next steps
- Phase 02 (env + compose) consumes the new files.
