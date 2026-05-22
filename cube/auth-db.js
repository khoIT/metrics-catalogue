// Auth DB lookup module.
//
// Exposes `getUserAccess(userId)` which returns the games and roles a user is
// allowed to use. The dev impl reads from a JSON file mounted into the
// container; production should replace the file-backed lookup with a real DB
// query without changing the public signature.

const fs = require('fs');

const USERS_FILE = process.env.AUTH_USERS_FILE || '/cube/conf/auth-users.json';

// File-backed cache. The JSON is small and rarely changes during a dev run;
// re-reading on every request would be wasteful. mtime check keeps it fresh
// without forcing a restart when an operator edits the seed file.
let cache = { mtimeMs: 0, users: null };

function loadUsers() {
  const stat = fs.statSync(USERS_FILE);
  if (stat.mtimeMs !== cache.mtimeMs) {
    const raw = fs.readFileSync(USERS_FILE, 'utf8');
    cache = { mtimeMs: stat.mtimeMs, users: JSON.parse(raw) };
  }
  return cache.users;
}

async function getUserAccess(userId) {
  // TODO(prod): replace this block with a real query against the auth DB,
  // e.g. `SELECT allowed_games, roles FROM cube_user_access WHERE user_id = $1`.
  // Keep the return shape identical so cube.js does not need changes.
  const users = loadUsers();
  const user = users[String(userId)];
  if (!user) {
    throw new Error(`Unknown user ${userId}`);
  }
  return {
    allowedGames: user.allowedGames || [],
    roles:        user.roles || [],
  };
}

module.exports = { getUserAccess };
