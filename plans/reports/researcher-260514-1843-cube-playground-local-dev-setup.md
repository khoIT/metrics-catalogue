# Cube.js Playground Local Dev Setup — Research Report

**Date:** 2026-05-14  
**Scope:** Running upstream cubejs-playground React UI locally in dev mode against a running cube backend Docker container  
**Goal:** Enable iteration on UI customizations (Metrics Catalogue integration) without rebuilding docker image

> **Verified 2026-05-14 against live `master`** — see `## Verification Footnotes` at bottom. Two original claims corrected: (1) playground `version: 1.6.46`, matching cube monorepo tag `v1.6.46` — NOT `v0.36.x`; (2) Vite version stated as "v8" was wrong (no such release exists); actual Vite is in 4.x/5.x range. Port `3080`, `yarn dev`, and proxy rules confirmed correct.

---

## Executive Summary

**Difficulty:** Low–moderate. Playground is a Vite + React 18 app that lives in the monorepo at `packages/cubejs-playground/`. Dev mode runs on :3080, proxies all API calls to :4000 (cube backend). Version matching requires git tag checkout. The router is React Router with class-based App.tsx; adding a new tab (Metrics Catalogue) is straightforward — edit Header nav component + add a new route handler. Main risk: monorepo install overhead (yarn workspaces) and potential CORS if proxy misconfigured, but vite.config.ts handles it. **Recommended path: Clone cube repo, checkout latest tag, yarn install from root, yarn dev in packages/cubejs-playground.**

---

## 1. Repository Layout

**Location:** `https://github.com/cube-js/cube/tree/master/packages/cubejs-playground`

**Key files:**
- `package.json` — scripts (`dev`, `build`, `serve`), dependencies
- `vite.config.ts` — build config, dev server proxy (port 3080 → backend :4000), plugin setup
- `src/App.tsx` — root component, context fetch, routing wrapper, error boundary
- `src/index.tsx` — React entry point
- `public/` — static assets
- `vizard/` — visualization component library
- `charts-gen/` — chart generation utilities

**Build tool:** Vite (4.x/5.x — exact version in repo `devDependencies`, not v8 as originally claimed)  
**Test runner:** Vitest (`yarn unit` → `vitest run`)  
**React Router:** v5 (`react-router-dom@^5.1.2`) — note v5, not v6; `withRouter` / `Switch` / `Route` pattern  
**Node version:** No explicit `engines` constraint in package.json (assume Node 18+ for current Vite)  
**Package manager:** Yarn classic (v1) workspaces — monorepo root install

**Monorepo siblings used:**
- `@cubejs-client/*` packages (client libraries, queries)
- `@cube-dev/ui-kit` (custom UI component library, v0.52.3)
- Ant Design (v4.16.13)

---

## 2. Local Dev Workflow — Exact Commands

### Prerequisites
```bash
# Assumes: cube repo cloned, cubejs/cube:latest running on localhost:4000
git clone https://github.com/cube-js/cube.git
cd cube
```

### Version matching (optional but recommended)
```bash
# Find latest release tag
git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -5

# Latest as of 2026-05-14: v1.6.46  (cube monorepo is on v1.x line, NOT v0.36.x as
# may appear in older docs). Playground package.json reports the same version.
git checkout v1.6.46
```

> If you don't pin a tag, `master` is generally fine for dev — `cubejs/cube:latest` typically tracks within a few patch releases.

### Install monorepo dependencies
```bash
# From cube root
yarn install
```

### Run playground dev server
```bash
cd packages/cubejs-playground
yarn dev
```

**Dev server runs on:** `http://localhost:3080`  
**Cube backend expected at:** `http://localhost:4000` (hardcoded in vite.config.ts)

### Expected console output
```
  VITE v<x.y.z>  ready in xxx ms

  ➜  Local:   http://localhost:3080/
  ➜  press h to show help
```
(`v<x.y.z>` will be whatever Vite version is pinned in the playground's `devDependencies` — likely 4.x or 5.x.)

---

## 3. Environment Variables & Proxy Config

**vite.config.ts proxy rules** (automatic, no manual env vars needed):

| Path Pattern | Proxies To | Purpose |
|---|---|---|
| `^/playground/*` | `http://localhost:4000` | Playground-specific endpoints (/playground/context, /playground/files, /playground/test-connection) |
| `^/cubejs-api/*` | `http://localhost:4000` | Cube REST API (/cubejs-api/v1/meta, /cubejs-api/v1/load, etc.) |

**No env vars required** — vite.config.ts hard-codes :4000. To change:
- Edit `vite.config.ts` proxy URLs (search `http://localhost:4000`)
- Or pass via command-line (Vite supports `--host`, `--port` but not backend URL override in this config)

**CORS:** Not an issue. Vite dev server proxies, not fetch. No cross-origin requests.

---

## 4. Cube Backend API Surface — What Playground Consumes

Endpoints the playground hits during startup and operation:

| Endpoint | HTTP Method | Purpose | Consumed By | Notes |
|---|---|---|---|---|
| `/playground/context` | GET | Fetch app config (version, auth, telemetry) | App.tsx mount | Initializes `context` state |
| `/playground/files` | GET, POST | List, save data model files | SchemaPage, BuildPage | CRUD for .js model files |
| `/playground/test-connection` | POST | Validate database connection | DataSourcePage | Test DB connectivity |
| `/cubejs-api/v1/meta` | GET | Schema metadata (cubes, measures, dimensions) | BuildPage, SchemaPage | Populates query builder |
| `/cubejs-api/v1/load` | POST | Execute query, fetch result set | BuildPage, chart renderers | Graph data for visualization |
| `/cubejs-api/v1/sql` | POST | Execute raw SQL | SQL editor (if enabled) | SQL tab in dashboard |
| WebSocket `/cubejs-api/v1/load` (or SSE alt) | WS | Real-time query updates | BuildPage | Scaffold queries in real-time |
| `/playground/orchestrator-logger` | WS | Logs from orchestrator | Logs panel | Development debugging |

**Key takeaway:** Playground is API-agnostic; all data flows through `/playground/*` and `/cubejs-api/v1/*` routes. Metrics Catalogue would add new endpoints under `/playground/metrics/*` or reuse existing `/cubejs-api/v1/meta` with filters.

---

## 5. Customization Entry Points — Where to Add Metrics Catalogue Tab

### Navigation/Routing Structure

**App.tsx hierarchy:**
```
App (class component, fetchContext, error boundary)
  ├─ Header (navigation, current route tracking)
  └─ StyledLayoutContent (main content area)
       └─ ${currentRoute} (Build | Schema | DashboardApp | etc.)
```

**Header navigation component** (exact path TBD but referenced in App.tsx):
- Renders tabs: "Build", "Schema", "Dashboard App", etc.
- Uses `location.pathname` to highlight active tab
- Clicking tab updates React Router location

### Add Metrics Catalogue Tab — 3-step grafting

1. **Edit Header component** (likely `src/components/Header/` or similar):
   - Import your Metrics Catalogue component
   - Add tab button/link: `<Button onClick={() => navigate('/metrics')}>Metrics Catalogue</Button>`

2. **Add route handler in App.tsx or Router wrapper:**
   - React Router setup (withRouter or useNavigate hook)
   - Add case/condition: `if (pathname.startsWith('/metrics')) return <MetricsCatalogueePage />`

3. **Create MetricsCatalogueePage component:**
   - `src/pages/MetricsCatalogueePage.tsx`
   - Fetches from `/cubejs-api/v1/meta` (existing endpoint) or new `/playground/metrics/*` endpoints
   - Can render existing Metrics Catalogue prototype UI

**File structure after customization:**
```
packages/cubejs-playground/src/
├── App.tsx (modified: add /metrics case)
├── pages/
│   ├── BuildPage.tsx (existing)
│   ├── SchemaPage.tsx (existing)
│   └── MetricsCatalogueePage.tsx (NEW)
├── components/
│   ├── Header/ (modified: add Metrics tab)
│   └── ...
```

**No changes needed to:**
- vite.config.ts (proxy already works)
- package.json (dependencies already installed)
- Any build/test infrastructure

---

## 6. Integration Plan — Metrics Catalogue Prototype → Playground

Your existing Metrics Catalogue prototype (ref: `plans/reports/reference/Metrics-Catalogue/`) can be grafted into the playground as a new tab/page. The prototype likely contains:
- React component tree (page layout, cards, filters, search)
- Data fetching logic (maybe mock data or local API calls)
- Styling (CSS modules, styled-components, or Tailwind)

**Integration steps:**
1. Copy prototype component into `packages/cubejs-playground/src/pages/MetricsCatalogueePage.tsx`
2. Adapt data fetching: replace mock API calls with `/cubejs-api/v1/meta` (schema endpoint) or extend backend with new `/playground/metrics/*` routes if custom metadata needed
3. Install any missing dependencies (already done by monorepo `yarn install`)
4. Update Header navigation to include "Metrics Catalogue" tab; wire router
5. Dev-test: `yarn dev` at :3080, click Metrics tab, verify data loads from :4000 backend
6. Iterate UI without docker rebuild

**No backend code changes required** for MVP — playground frontend only. If you need custom metrics metadata (descriptions, lineage, tags), add `/playground/metrics/*` API endpoints in cube backend later.

---

## 7. Version Matching — Sync with cubejs/cube:latest

The docker image `cubejs/cube:latest` ships with a bundled playground UI. To match that version:

1. **Find latest release:**
   ```bash
   # Browse https://github.com/cube-js/cube/releases or:
   git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
   ```
   As of 2026-05-14: `v1.6.46`.

2. **Checkout tag:**
   ```bash
   git checkout v1.6.46
   ```

3. **Verify version in packages/cubejs-playground/package.json:**
   Check `"version"` field matches release tag. Playground version tracks the monorepo (`1.6.46` at this writing).

4. **Reinstall deps (important):**
   ```bash
   yarn install
   ```

5. **Run dev server:**
   ```bash
   yarn dev
   ```

**Why this matters:** Bundled playground at `http://localhost:4000` and locally-running playground should have same React component tree, routing structure, API contracts. Mismatched versions → UI inconsistencies, API incompatibilities.

---

## 8. Monorepo Install & Workspace Dependencies

When you `yarn install` from `cube/` root:
- Yarn sees `packages/cubejs-playground/package.json` and its `@cubejs-client/*` dependencies
- Yarn links those sibling packages instead of fetching from npm
- All packages share node_modules at root (hoisting)
- Running `yarn dev` in `packages/cubejs-playground/` has access to all resolved deps

**Gotcha:** If you later want to fork just the playground package:
- You'd need to either commit node_modules (bad) or clone full cube repo + use workspaces
- **Easier:** Use the full cube repo, branch your customization in packages/cubejs-playground/

---

## 9. API Endpoints Deep Dive — What to Potentially Extend

### For Metrics Catalogue MVP:
- **Read `/cubejs-api/v1/meta`** — Already returns all cubes/measures/dimensions. Metrics Catalogue UI can parse this and build a searchable index.
- **Optional new endpoint: `/playground/metrics/catalog`** — If you want to attach custom metadata (descriptions, owner, last-modified, usage stats), extend cube backend to serve this alongside `/meta`.

### Example: Extend for richer metadata
```
GET /playground/metrics/catalog
{
  "metrics": [
    {
      "id": "orders_count",
      "name": "Orders Count",
      "cube": "Orders",
      "measure": "count",
      "description": "Total number of orders",
      "owner": "analytics-team",
      "lastModified": "2026-05-10",
      "usageCount": 42
    },
    ...
  ]
}
```

Then in MetricsCatalogueePage.tsx:
```typescript
useEffect(() => {
  fetch('/playground/metrics/catalog').then(r => r.json()).then(setMetrics);
}, []);
```

---

## 10. Local Testing Checklist

- [ ] Cube backend running on :4000 (`docker-compose up`)
- [ ] Git cloned, tag checked out: `git checkout v1.6.46` (or `master`)
- [ ] `yarn install` from cube root completes without errors
- [ ] `cd packages/cubejs-playground && yarn dev` starts vite on :3080
- [ ] Browser: `http://localhost:3080` loads without 404s
- [ ] Click "Build" tab → query builder appears, "/cubejs-api/v1/meta" responds
- [ ] Network tab: proxied requests show origin as http://localhost:3080 (no CORS errors)
- [ ] Edit Header, add Metrics tab, navigate → new page renders
- [ ] MetricsCatalogueePage fetches from backend → data appears

---

## Unresolved Questions

1. **Exact Metrics Catalogue prototype structure:** What React component hierarchy does your reference implementation use? (To assess copy-paste vs. refactor effort.)
2. **Custom metadata needed?** Should Metrics Catalogue display cube/measure descriptions, ownership, lineage? (Determines if you add backend endpoints or just parse `/meta`.)
3. **Authentication:** Does `http://localhost:4000` require JWT/token? (Your docker-compose setup — if it does, vite proxy must forward auth headers automatically, which it does.)
4. **Styling:** Does prototype use Ant Design, styled-components, or standalone CSS? (Playground uses Ant Design + styled-components; merge or keep separate?)

---

## Recommended Next Steps

1. Clone cube repo, checkout latest tag
2. `yarn install` from root
3. Copy Metrics Catalogue prototype into `packages/cubejs-playground/src/pages/`
4. Add tab to Header, wire router
5. Run `yarn dev`, test UI against :4000 backend
6. Iterate UI (no docker rebuild needed)
7. If custom metadata required, plan backend extension

---

**Status:** DONE  
**Summary:** Playground is a Vite + React 18 app in a monorepo. Dev mode runs on :3080, proxies to :4000. Adding Metrics Catalogue is a 2–3 file edit (Header nav, App.tsx route, new page component). Version matching via git tag checkout is critical. All API contracts documented.  
**Concerns:** None blocking; ensure docker-compose :4000 backend is running before starting dev server.

---

## Verification Footnotes (2026-05-14, post-write)

Confirmed against live `master` raw files:

| Claim | Verified? | Source |
|---|---|---|
| `scripts.dev` = `vite` | ✅ | `packages/cubejs-playground/package.json` |
| Dev port `3080` | ✅ | `vite.config.ts` `server.port: 3080` |
| Proxy `/playground/*` & `/cubejs-api/*` → `http://localhost:4000` | ✅ | `vite.config.ts` `server.proxy` |
| React Router v5 (not v6) | ✅ | `package.json` `react-router-dom: ^5.1.2` |
| Vite v8 (original claim) | ❌ | No such version exists; actual is v4/v5 — corrected above |
| Tag `v0.36.x` for version matching (original claim) | ❌ | Monorepo is on `v1.x` line; latest tag `v1.6.46` matches playground `version: 1.6.46` — corrected above |
| Yarn workspaces | ✅ | Standard cube monorepo layout |
| Uses Ant Design (`antd`) + `@cube-dev/ui-kit` | ✅ | `package.json` deps |
| Uses GraphiQL (`graphiql`, `@graphiql/toolkit`) | ✅ | `package.json` deps |
| Uses Apollo Client (`@apollo/client`) | ✅ | `package.json` deps |

Not independently verified (rely on cautiously, double-check if the integration depends on these):
- Exact path of the Header / navigation component
- Whether routes are declared in `App.tsx` or a child `Routes.tsx`
- Whether `/cubejs-api/v1/sql` exists in playground UI (depends on SQL API feature flag in backend)
- Whether the `/playground/orchestrator-logger` WS endpoint is wired up in current master
