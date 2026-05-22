// Multi-tenant Cube config for the game_integration Trino catalog.
//
// Each request carries a JWT identifying the calling user and the game they
// want to query. We resolve the user's allowed games against the auth DB,
// reject cross-tenant access, then route the request to the correct Trino
// schema. Compile cache and pre-aggregation storage are namespaced per game.
//
// JWT shape (HS256, signed with CUBEJS_API_SECRET):
//   { userId: <number|string>, game: "ballistar"|"cfm"|"ptg"|"jus", iat: ... }

const jwt = require('jsonwebtoken');
const { getUserAccess } = require('./auth-db');

// Game key (used in JWT + URLs) -> Trino schema under the game_integration catalog.
// Schema names are stable and live in Trino; only this map ever needs to grow.
const GAME_SCHEMA = {
  ballistar: 'ballistar_vn',
  cfm:       'cfm_vn',
  ptg:       'ptg',
  jus:       'jus_vn',
};

const SUPPORTED_GAMES = Object.keys(GAME_SCHEMA);

// Synthetic context used by the scheduled refresh worker. It bypasses the
// JWT path entirely, so we tag it with a sentinel role that queryRewrite
// (and future accessPolicy rules) can recognise as "system, not human".
const REFRESH_ROLE = '__refresh__';

function buildSecurityContext(payload, access) {
  return {
    userId:       payload.userId,
    game:         payload.game,
    allowedGames: access.allowedGames,
    roles:        access.roles,
  };
}

module.exports = {
  // 1. Authenticate every incoming request: verify JWT, resolve access from
  //    the auth DB, enforce that the requested game is allowed for this user.
  checkAuth: async (req, auth) => {
    if (!auth) {
      throw new Error('Authorization header missing');
    }
    const payload = jwt.verify(auth, process.env.CUBEJS_API_SECRET);
    const game = payload.game;
    if (!SUPPORTED_GAMES.includes(game)) {
      throw new Error(`Unknown or missing game claim: ${game}`);
    }
    const access = await getUserAccess(payload.userId);
    if (!access.allowedGames.includes(game)) {
      throw new Error(`User ${payload.userId} not allowed for game ${game}`);
    }
    req.securityContext = buildSecurityContext(payload, access);
  },

  // 2. Per-tenant compile cache. Cube keeps one compiled schema per appId,
  //    so changes in one tenant's metadata don't invalidate the others.
  contextToAppId: ({ securityContext }) =>
    `cube_${securityContext.game}`,

  // 3. Per-tenant orchestrator. Pre-aggregation storage in Cube Store is
  //    keyed by orchestratorId, so each game gets its own rollup namespace.
  contextToOrchestratorId: ({ securityContext }) =>
    `orch_${securityContext.game}`,

  // 4. Per-tenant Trino driver. Same catalog, swap the schema. Existing
  //    cube YAMLs use bare sql_table values, so this is the only place the
  //    schema name appears in code paths.
  driverFactory: ({ securityContext }) => ({
    type:    'trino',
    host:    process.env.CUBEJS_DB_HOST,
    port:    process.env.CUBEJS_DB_PORT,
    user:    process.env.CUBEJS_DB_USER,
    password: process.env.CUBEJS_DB_PASS,
    catalog: process.env.CUBEJS_DB_PRESTO_CATALOG,
    schema:  GAME_SCHEMA[securityContext.game],
    ssl:     process.env.CUBEJS_DB_SSL === 'true',
  }),

  // 5. Refresh worker must enumerate every tenant or it only ever refreshes
  //    the first one it sees. We mint synthetic contexts (no JWT, all games
  //    allowed to self) tagged with REFRESH_ROLE so RLS rules can skip them.
  scheduledRefreshContexts: async () =>
    SUPPORTED_GAMES.map((game) => ({
      securityContext: {
        userId:       `refresh:${game}`,
        game,
        allowedGames: [game],
        roles:        [REFRESH_ROLE],
      },
    })),

  // 6. RLS extension point. Today this is a pass-through; per-user / per-role
  //    row filters get added here as the auth DB grows. Pattern:
  //
  //      if (!securityContext.roles.includes('admin')) {
  //        query.filters.push({
  //          member: 'recharge.user_id',
  //          operator: 'equals',
  //          values: [String(securityContext.userId)],
  //        });
  //      }
  queryRewrite: (query, _ctx) => query,
};
