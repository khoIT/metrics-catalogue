# Phase 03 — Smoke test and docs

## Context links
- Plan overview: [plan.md](./plan.md)
- Phase 01: [phase-01-multi-tenant-cube-config.md](./phase-01-multi-tenant-cube-config.md)
- Phase 02: [phase-02-env-and-compose-updates.md](./phase-02-env-and-compose-updates.md)

## Overview
- **Priority:** P1 (validation + handoff)
- **Status:** pending
- Add a per-game smoke test, a JWT-mint helper, and a README section so the
  next developer can boot the multi-tenant flow from a clean clone.

## Requirements
**Functional**
- Smoke test exercises each of the 4 games and one negative case (cross-game
  rejection).
- Helper script mints valid JWTs without forcing developers to write Node.
- README section explains JWT shape, authDB JSON schema, and how to add a user.

## Related code files
**Create**
- `examples/00_mint_jwt.sh` — minimal helper, prints a JWT for given `userId` + `game`.
- `examples/05_test_multi_tenant.sh` — calls Cube REST API once per game + one rejected call.

**Modify**
- `README.md` — add a "Multi-tenant" section near the existing architecture
  notes; update auth section to point at JWT shape.

## Implementation steps
1. `examples/00_mint_jwt.sh`:
   - `set -euo pipefail`, read `CUBEJS_API_SECRET` from env.
   - Accept `userId` and `game` as positional args (or `--user`, `--game`).
   - Use `node -e "console.log(require('jsonwebtoken').sign({userId,game}, secret))"`.
   - Print token to stdout so it can be `$(...)`-captured.
2. `examples/05_test_multi_tenant.sh`:
   - Source pattern matches `01_test_rest_api.sh`.
   - For each game in `{ballistar, cfm, ptg, jus}`:
     - Mint JWT for a single-game user using `00_mint_jwt.sh`.
     - POST a tiny query (`mf_users.user_count_approx`) and `jq` the result.
   - One negative-path call: JWT for a `ptg`-only user requesting against
     `game=cfm` JWT (via `--game cfm` minting flow with a `ptg`-only userId
     in seed data) — expect HTTP 4xx + error JSON.
3. `README.md`:
   - New section "Multi-tenant (game_integration)":
     - JWT shape `{ userId, game }`.
     - authDB seed location + how to add a user.
     - How dev mode interacts (it doesn't — must be off).
     - Pointer to `examples/05_test_multi_tenant.sh`.
   - Cross-link existing "Production checklist" line about JWT.

## Todo list
- [ ] `examples/00_mint_jwt.sh` created and `chmod +x`
- [ ] `examples/05_test_multi_tenant.sh` created and `chmod +x`
- [ ] README "Multi-tenant" section added
- [ ] Manual run: all 4 games return data; negative case returns 4xx

## Success criteria
- Running `bash examples/05_test_multi_tenant.sh` against a configured
  Trino backend prints non-empty results for each game and a clear error
  for the cross-game attempt.

## Risk assessment
- **Risk:** Smoke test fails because Trino schemas for cfm / ptg / jus don't
  exist yet in the catalog. **Mitigation:** README explicitly notes this is
  expected; the test still validates routing (queries reach Trino with the
  right schema, errors come from Trino, not Cube).

## Next steps
- Optional follow-up: TTL cache in `auth-db.js`.
- Optional follow-up: real DB driver for `getUserAccess`.
- Optional follow-up: first `queryRewrite` rule when first RLS requirement lands.
