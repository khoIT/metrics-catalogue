# Research Report — Raw Events Exploration UI for Feature-Store Requests

> **Date:** 2026-05-13 16:59 (Asia/Saigon)
> **Author:** researcher (Claude)
> **Scope:** Marry Hermes Feature Store (`code/hermes`) with a new Cube-fronted "Explore → Propose Metric" surface that lets non-tech LiveOps PMs walk in cold, browse raw `ballistar_vn` events, and file a feature/metric request that lands in the Hermes registration pipeline.
> **Methodology:** 1× local repo scan + 4× WebSearch (Gemini CLI auth failed, fell back). Sources at end.

---

## Executive Summary

The current Cube surface (Playground + SQL on `:15432`) is **analyst-grade**, not PM-grade. Hermes already ships the *downstream* half of what the user wants — Feature Store library, threshold playground, register-a-feature flow, provenance dots, health verdicts, chat-driven agent UX. Hermes's `Explore` module is a **stub**. That stub is the missing surface.

The job-to-be-done is a **three-step funnel**:

1. **Land** — non-tech PM opens a chat or a "browse events" entry-point.
2. **Explore** — they pivot through raw event streams (cohort, funnel, flow, distribution) without writing SQL, with provenance shown at every step.
3. **Propose** — they save the exploration as a draft feature-request that prefills `/feature-store/new`, attaches the SQL/predicate the system actually executed, and routes to the engineering queue.

SOTA in 2025–2026 has converged on four patterns:

| Pattern | Anchor product | Why it matters here |
|---|---|---|
| **Semantic-layer-anchored NL** | Snowflake Cortex Analyst (~90% accuracy), Lightdash AI Agent, Hex Magic | Cube YAML is exactly the semantic spec needed to ground LLM queries — Cube is *already* the right substrate, the UI is the gap |
| **Three-pane reasoning view** | Hex Threads, ThoughtSpot | NL question → visible reasoning (SQL/predicate) → result. PMs read top + bottom; engineers audit middle |
| **Event explorer primitives** | Amplitude / Mixpanel / Heap | Funnel, Cohort, Retention, Flows — these are the **only** four UX shapes non-tech users actually use to "explore raw events"; build these or watch users bounce |
| **Proactive surfacing** | Tableau Pulse, Mixpanel Spark, Hermes "Hermes noticed" | Don't make PMs ask — push anomalies / new-feature suggestions into the inbox |

The strategic recommendation: **don't build a generic Cube UI replacement.** Build a `cube-dev/web` companion (or extend Hermes `Explore`) that is a thin opinionated front for the four event-explorer primitives, talks to Cube via SQL API, and ends every flow with a "Propose this as a metric" button wired to Hermes's existing `registerFeature()` path.

---

## 1. What Hermes Already Has (and What It Lacks)

### 1.1 Feature Store v2 — the downstream half is solid

`hermes/apps/web/src/modules/feature-store/` ships:

- **Library** (`library.tsx`) — 76 features, stat strip, filter rail (Type · Latency · Games · Platform · Status), group-by (Domain / Game / Tier / Status / Platform), 4 sort strategies, drift-detected entry-point
- **Detail** (`detail.tsx`) — 3 persona tabs (LiveOps / Analyst / Engineer) with:
  - LiveOps: SourceProvenanceCard (🟢 real / 🟠 hybrid / ⚪ synth), HealthVerdictCard, **ThresholdPlaygroundPanel** (slider over `feature_values` → 200ms live audience count from 6.35M rows)
  - Analyst: Quantile Strip, Coverage Segmentation, Sample Value Cards, Correlated Features (Pearson on 5k sample), Outliers (z-score)
  - Engineer: Pipeline Health Timeline, Cost & Latency, Lineage v2 (upstream/downstream), Backfill History
- **Register** (`register.tsx`) — `/feature-store/new` route with 6-section form, snake_case validation, Platform auto-suggest at ≥3 games, handoff modal mirroring segment/campaign handoffs
- **Backend wiring**: `catalog-api` exposes `/features/*` endpoints; `query-svc` runs AND-of-OR predicates as Postgres INTERSECT/UNION/EXCEPT (33,813 uids · 153ms across 6.35M rows per demo script)

### 1.2 The chat substrate is built — and reusable

`hermes/apps/web/src/modules/chat/` already ships multi-turn analyst threads, `HermesNoticedPanel` (proactive surfacing), tool-call chips with provenance footers, and Path B (agent-first demo). The conversational entry-point a PM needs to *explore* events is already 80% built — it just doesn't talk to Cube or to raw event tables yet.

### 1.3 The `Explore` module is a stub

`hermes/apps/web/src/modules/explore/` exists but `docs/codebase-summary.md` and README §Modules list it under "Knowledge / Funnels / Retentions / Playbooks / Explore — Stubs for future surfaces." This is the **exact** surface the user is asking us to design.

### 1.4 The metric/feature **request** path doesn't exist yet

Today's `registerFeature()` (per PRD Phase 4) pushes onto an **in-memory catalog with no backend persistence**. PMs can prototype a feature spec but there's no:
- Engineering queue / triage workflow
- "I want X" stub-state where the spec exists but the materialization doesn't
- Bridge from an *exploration* (a saved funnel/cohort) → a *feature request*
- Auto-generated SQL/predicate scaffold from the exploration

That last point is the highest-leverage missing piece — when a PM has built a 4-step funnel + cohort filter in the explorer, the system already knows the dbt SQL it would compile to. Handing that to engineering as a request is nearly free.

---

## 2. Current Cube UI — Honest Assessment

What exists today in `cube-dev`:

| Surface | Audience served | Audience NOT served |
|---|---|---|
| Cube Playground (`:4000`) | Engineer trying YAML | Any PM |
| SQL API (`:15432`) | Analyst with psql + cube-SQL syntax knowledge | Any PM |
| REST/GraphQL APIs | Application integrator | Anyone interactively exploring |

**Brutal verdict:** Cube has zero UI for the JTBD as stated. It has a *developer-tool* (Playground) and a *protocol surface* (SQL API). Selling Playground to a LiveOps PM in CFM/NTH and asking them to write `MEASURE(active_daily.dau)` will fail in user testing within 30 seconds. The user's framing — "improve current cube UI" — is generous; the realistic framing is **add a PM-facing tier above Cube**, with the Playground reserved for engineers debugging the YAML.

---

## 3. SOTA Patterns Worth Stealing (2025–2026)

### 3.1 Semantic-layer-grounded NL (the accuracy lever)

Generic text-to-SQL on raw schemas hallucinates. Cortex Analyst, Genie, Lightdash AI Agent, Hex Magic all converged on the same insight: **ground the LLM in a semantic layer**, not raw DDL. Cortex Analyst claims ~90% accuracy specifically because it has a Snowflake semantic model in the prompt context.

→ **Direct implication for us:** Cube YAML *is* the semantic model. A "Ask Cube anything" chat that gets `cube/model/cubes/*.yml` + `cube/model/views/*.yml` in its system prompt + tool-call to SQL API will outperform any schema-only baseline on day one. Lightdash even goes further: the AI **proposes semantic-layer updates** while answering — when a PM asks for a metric that doesn't exist yet, the agent drafts the YAML and files a PR. That is **exactly** the feature-request workflow the user is asking for, reframed.

### 3.2 Three-pane reasoning view

Hex Threads / Cortex Analyst / Genie all show three vertical zones:

```
┌───────────────────────────────────────────────────────────────┐
│ NL QUESTION (PM-readable)                                     │
│ > "How many new users in CFM last week never came back?"      │
├───────────────────────────────────────────────────────────────┤
│ REASONING STEPS (collapsible — engineer audit lane)           │
│  step 1: WITH new_users AS (SELECT ... FROM active_daily ...) │
│  step 2: LEFT JOIN active_daily a2 ON ... WHERE a2.dt IS NULL │
│  step 3: COUNT(DISTINCT user_id) → 12,481                     │
├───────────────────────────────────────────────────────────────┤
│ RESULT + VISUAL                                               │
│  [bar chart 12,481 lost · 41,202 retained · 23.2% drop]       │
│                                                               │
│  [ Save as cohort ] [ Propose as metric ] [ Pin to canvas ]   │
└───────────────────────────────────────────────────────────────┘
```

PMs read top + bottom and ignore middle. Engineers expand middle to verify before approving the metric request. **Both audiences served by the same artifact.**

### 3.3 The four explorer primitives (Amplitude / Mixpanel canon)

Non-tech users in product analytics in 2026 still rely on the same four shapes that Amplitude shipped a decade ago:

| Primitive | Question it answers | Cube cube/view it maps to |
|---|---|---|
| **Funnel** | What % of users get from step A to step B to step C? | A view over `active_daily` + event-typed measures |
| **Cohort** | Among users who did X on date D, what % did Y by D+N? | `mf_users` cohort dim + `user_recharge_daily` time-series |
| **Retention** | Of users acquired on day 0, who's still active on day N? | `active_daily` with rolling time joins |
| **Flow / Path** | What sequence of events leads to (or away from) X? | Requires session-stitching — currently NOT in `ballistar_vn` cubes |

The first three are buildable on the current four cubes with maybe one new measure each. **Flow/path is the gap** — it needs a sessionized event stream upstream of Cube (likely a dbt model). Worth scoping but don't block v1 on it.

### 3.4 Proactive surfacing ("don't make me ask")

Tableau Pulse, Mixpanel Spark, and Hermes's own `HermesNoticedPanel` all share one move: **a daily inbox of anomalies the user didn't ask for**. Hermes already has the UI shell. Wiring it to Cube refresh-keys (drift scores already computed in `analytics.driftScore`) and pre-agg freshness SLA misses is incremental. This is how PMs *start* sessions — not by going to "Explore" but by clicking a card that says "CFM ARPDAU dipped 7%, want to investigate?"

### 3.5 Provenance is a competitive advantage, not table stakes

Hermes's 🟢/🟠/⚪ dot is unusual — Amplitude / Mixpanel don't surface data freshness or synthesis-status to end users. Keep this. In the new explorer, **every chart needs a provenance footer**: which cube, which pre-agg (if matched), last refresh, sample-vs-full. This is the trust gradient that lets a PM bet a campaign on a number.

---

## 4. Proposed UI — "Explore → Propose" Flow

### 4.1 Information architecture

```
┌── /explore (new — Hermes module, or new cube-dev/web app) ────────────────┐
│                                                                            │
│ ┌─ Landing ────────────────────────────────────────────────────────────┐  │
│ │  ✨ Hermes noticed                                                    │  │
│ │  • CFM new-user retention down 4pp last 14d  →  [Investigate]        │  │
│ │  • Recharge funnel step-2 drop-off spiked Tue →  [Investigate]       │  │
│ │  • 3 features drifted ≥0.4 (see Feature Store) →  [Open list]        │  │
│ │                                                                       │  │
│ │  Or start fresh:                                                      │  │
│ │  [ 💬 Ask a question ]  [ 📊 Build a funnel ]                        │  │
│ │  [ 👥 Define a cohort ] [ 📈 Retention curve ]                       │  │
│ └──────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│ ┌─ Workspace (after entry) ────────────────────────────────────────────┐  │
│ │  Question / config  →  Reasoning (cube SQL)  →  Chart + audience #   │  │
│ │                                                  + 🟢 provenance     │  │
│ │  Right rail: dimensions & measures palette (drag in)                 │  │
│ │  Bottom bar: [Save exploration] [Pin] [Propose as metric →] [Share]  │  │
│ └──────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  │  "Propose as metric"
                                  ▼
                  /feature-store/new?fromExploration=<id>
                  (prefilled name, domain, latency,
                   dbt SQL scaffold, propensity flags off,
                   description: PM's last NL question)
```

### 4.2 The four primitives — concrete UX

#### A. Ask-a-question (NL, primary entry)

- Chat input over the same chat substrate Hermes already has (`HermesNoticedPanel` style)
- LLM gets `cube/model/**/*.yml` + view definitions + dim/measure descriptions as system context
- Tool-call: `cube.sql(query, params)` against `:15432`
- Response = three-pane (question / SQL / chart) per §3.2
- Multi-turn: "now break that down by region", "now exclude the whales" — each turn appends to the same exploration

#### B. Funnel builder (drag-drop, no NL needed)

```
Step 1: [event ▼]  Filter: [+] [region = VN ×]
Step 2: [event ▼]  Filter: [+]
Step 3: [event ▼]  Filter: [+]    Window: [7d ▼]

→ live: 100% → 41% → 12% (Σ=12,481)
[Save as cohort] [Propose conversion-rate metric]
```

Each step compiles to a Cube query against `active_daily` or similar. Steps autocomplete from declared event types in the YAML.

#### C. Cohort builder (the existing Hermes ThresholdPlayground generalized)

Hermes already has single-feature slider. Generalize to AND-of-OR with the **same UX the Segments module already uses** — no new component needed, just point it at exploration-time queries instead of pre-registered features.

#### D. Retention curve

Pick a "starting event" + a "returning event" + a window. Output a heatmap (day-N retention by acquisition cohort). Trivial Cube query against `active_daily` once a `user_first_seen_dt` dim is added.

### 4.3 The "Propose as metric" CTA — the part that doesn't exist anywhere

This is the differentiating move. When a PM has built any exploration:

1. Click **Propose as metric**
2. Modal pops with:
   - **Name** (snake_case) — LLM-suggested from the NL question
   - **Domain / Latency** — inferred from cubes touched
   - **dbt SQL scaffold** — generated from the exploration's compiled query (the engineer can polish)
   - **Description** — the PM's own NL question, verbatim
   - **Requested freshness** — PM picks Realtime / Batch warm / Batch cold
   - **Use case** — free-text ("I want to use this for a rescue campaign in CFM")
3. Submit → creates a **draft feature** in Hermes (`status: 'requested'`, `lastBackfillAt: null`) + a row in a new engineering queue
4. Engineering reviews → polishes SQL → flips status to `active` → backfill triggers
5. PM gets a notification in `HermesNoticedPanel`: "Your requested metric `cfm_session_recovery_rate` is live"

The clever bit: **the PM never wrote SQL but the queue has working SQL to start from.** That's the conversion lever from "shadow Excel work" to "things engineering can actually ship."

---

## 5. Build Recommendation (KISS / YAGNI ordered)

Phase ordering — **do not build all of this**. The first three deliver 80% of value.

| # | Deliverable | Effort | Why first |
|---|---|---|---|
| 1 | Wire Hermes chat → Cube SQL API with YAML in system prompt | S | Highest leverage; substrate exists; ship behind a feature flag |
| 2 | Three-pane reasoning view in chat (question / SQL / chart + provenance footer) | M | Trust gradient; engineer audit lane |
| 3 | "Propose as metric" CTA → prefill `/feature-store/new` from chat | M | Closes the loop; **this is the unique JTBD** |
| 4 | Funnel builder primitive | M | First non-NL primitive; most-requested in product analytics surveys |
| 5 | Generalize ThresholdPlayground → multi-feature cohort builder | S | Already 80% built |
| 6 | Retention curve primitive | M | Useful but lower-frequency than funnels |
| 7 | Engineering queue + status flips + notification loop | M | Requires backend (catalog-api persistence) |
| 8 | Flow/Path primitive (requires sessionized events upstream) | L | Deferrable — out of scope until dbt sessions land |

**Reject for now:**
- A Cube Playground replacement (engineer tool — leave it alone)
- A Tableau-style pixel-perfect dashboard builder (`/canvas` already covers pinning)
- Generic text-to-SQL on raw `ballistar_vn` tables (semantic-grounded only — the accuracy delta is too large to bypass)

---

## 6. Risks & Open Questions

| Risk | Mitigation |
|---|---|
| Cube SQL API latency on cold queries (~4.5s per README) feels bad in chat | Show streaming "reasoning" middle pane while query runs; cache by question hash |
| LLM hallucinates a cube/measure that doesn't exist | Hard-fail with "I don't have a measure for X — propose it?" → routes directly to step 3 |
| `feature_values` Postgres table (Hermes) and Cube semantic layer drift apart | Single source of truth must be one or the other for any *given* metric; document the contract |
| Non-tech users still find funnels intimidating | Start every session with the `Hermes noticed` inbox; "fresh exploration" is the secondary path |
| Engineering queue becomes a junk pile | Require a `use_case` field + an estimated reach (auto-computed from the exploration's audience count) before submit |

### Unresolved

- Does `cube-dev` ship its own web app or extend Hermes `Explore`? (Affects ownership and deploy story — Hermes is React/Vite, cube-dev currently has no frontend.)
- Where does the engineering queue live — Hermes `catalog-api` or a new table in Cube Store? (Recommend Hermes; it already has Postgres.)
- Should the LLM be allowed to **propose YAML edits** Lightdash-style, or only file requests? (Recommend file-only for v1 — proposing edits crosses a governance line.)
- Sessionization of `ballistar_vn` events for Flow primitive — out of scope here, but blocking #8.
- Is there an existing event-type registry, or do we generate the funnel-step picker from cube measures? (Affects builder UX.)

---

## Sources

- [10 Data Exploration Tools for 2026: Features & Picks — Domo](https://www.domo.com/learn/article/best-data-exploration-tools)
- [Self-service analytics tools 2026 — Querio](https://querio.ai/articles/best-self-service-analytics-tools-why-legacy-analytics-fall-short)
- [10 Best Self-Service Analytics Tools for 2026 Product Teams — Userpilot](https://userpilot.com/blog/self-service-analytics-tools/)
- [Mixpanel vs Amplitude — Userpilot](https://userpilot.com/blog/mixpanel-vs-amplitude/)
- [Best AI Product Analytics Tools in 2026: Amplitude vs Mixpanel vs PostHog vs Heap — Techno-Pulse](https://www.techno-pulse.com/2026/05/best-ai-product-analytics-tools-in-2026.html)
- [Your semantic layer can now fix itself — Lightdash](https://www.lightdash.com/blogpost/your-semantic-layer-can-now-fix-itself)
- [Fall 2025 Launch: Agents, for analytics, for teams — Hex](https://hex.tech/blog/fall-2025-launch/)
- [Databricks Data + AI Summit 2025: Semantic layer advantage — Lightdash](https://www.lightdash.com/blogpost/databricks-2025-recap)
- [The Future of AI/BI: Snowflake Cortex Analyst vs Databricks Genie — Deepa Nair / Medium](https://medium.com/@nair.g.deepa/the-future-of-ai-bi-snowflake-cortex-analyst-vs-databricks-genie-6b65073a43c6)
- [Snowflake launches Cortex Analyst (agentic AI) — VentureBeat](https://venturebeat.com/data-infrastructure/snowflake-launches-cortex-analyst-an-agentic-ai-system-for-accurate-data-analytics)
- [Best AI Data Analysis Agents in 2026 (12 platforms compared) — Tellius](https://www.tellius.com/resources/blog/best-ai-data-analysis-agents-in-2026-12-platforms-compared-for-nl-to-sql-autonomous-investigation-and-governance)
- [Cortex Analyst documentation — Snowflake](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)

### Local sources

- `/Users/lap16299/Documents/code/hermes/README.md`
- `/Users/lap16299/Documents/code/hermes/docs/feature-store-v2-prd.md`
- `/Users/lap16299/Documents/code/hermes/docs/feature-store-demo-script.md`
- `/Users/lap16299/Documents/code/hermes/apps/web/src/modules/` (directory listing)
- `/Users/lap16299/Documents/code/cube-dev/docs/journals/260513-1629-cube-semantic-layer-foundation.md` (prior session output, referenced not re-read)
