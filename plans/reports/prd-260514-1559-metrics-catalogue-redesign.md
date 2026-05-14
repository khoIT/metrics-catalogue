# Design PRD: Metrics Catalogue v2 — Event Semantics + Three-Layer Metric Authoring

**Audience:** Claude Design (paste-ready)
**Companion research:** `researcher-260514-1547-event-semantics-and-metric-builder-ux.md`
**Codebase:** `plans/reports/reference/Metrics-Catalogue/` — single-page React-on-CDN, JSX edits only, custom design system
**Date:** 2026-05-14 (rev 17:00 — concise rewrite + Cube-cross-walk decisions)

---

## 1. Problem & job-to-be-done

A non-tech PM sits in front of raw events on a Cube semantic layer over Trino. Job: **understand the data → validate a hypothesis → mint a new metric** that the data pipeline materializes and serves through a feature store.

**v1 demo gaps:**
- Semantic enrichment is shallow (description-only).
- The formula bar floats above a hardcoded measure list — a PM cannot mint a new measure from a raw event.
- Vocabulary collapses "measure" and "metric" into one ambiguous label.
- The "register" button is a stub.
- Home is event-first; Cube's queryable surface is view-first.

**The fix — three layers + view-first nav + PR-based register:**

```
Layer 0  Raw event           events.jsx (drill-down inside a view)
Layer 1  Measure (primitive) measure.jsx (NEW — 9 cards)
Layer 2  Derived metric      formula.jsx (Templates + Custom formula tabs)
Register → opens PR → review → merge → catalogue-materializer service → live
```

---

## 2. Resolved decisions (anchor)

| Decision | Resolution |
|---|---|
| Vocabulary | **Separate.** Layer 1 = *measure* (Cube atom). Layer 2 = *derived metric* (`type: number` over measure refs). Umbrella = *catalogue entry*. "Metric" alone never appears in UI. |
| Times-per-user materialization | **Cube `pre_aggregations:` grouped by `user_id`.** Card emits the block; outer agg = a measure that reads from the pre-agg. |
| Register output | **Pull Request → human approval → `catalogue-materializer` service.** State machine: `draft → in_review → approved → materializing → live`. |
| Home entry | **Views-first.** Home lists Cube views; events become a drill-down inside a view's "Source events" tab. |
| Custom SQL escape hatch | **In scope as a 9th card "Custom SQL (Expert)".** Hidden behind an Expert toggle. |
| Time-window filters | **`<FilterBuilder />` gains a Relative-window operator** + new `<DateRangePicker />` for custom ranges. |

---

## 3. Design principles (non-negotiable)

1. One decision per screen — each layer = one screen.
2. Two fields max per primitive (Custom SQL excepted).
3. Live value preview, always.
4. Read-only Cube YAML preview on every authoring screen.
5. Provenance dot + compliance badge (`✓ verified / ⚠ incomplete / ⛔ deprecated`) on every artifact.
6. Compliance is informational, never blocking.
7. Inherit existing design tokens (`--orange-600`, `--blue-700`, `font-mono`, `Pill`, `Badge`, `Button`, `Icon`, `ProvDot`, `formula-bar`, `radius-md`, `shadow-lg`).
8. Keyboard-first formula editing — preserve cursor-aware operator + A/B/C insert.

---

## 4. Information architecture

```
Home (home.jsx, NEW — view picker)
└── Explore
    ├── Views (view.jsx, NEW — per-view detail)
    │   └── Source events → events.jsx drawer overlay
    └── (later) Tables
└── Build
    ├── Measure (measure.jsx, NEW — 9 primitives)
    ├── Derived metric (formula.jsx — was "Metric")
    ├── Funnel / Cohort / Flow / Retention (unchanged)
└── Library (library.jsx — split by badge in v2.1)
└── Register handoff (register.jsx — PR-based)
```

**Primary flow:**

```
home → pick view → view.jsx
  ├─ Source events tab → click event → drawer (Metadata/Properties/Lineage)
  │     → action grid → [Define a measure] → measure.jsx
  └─ "Define a measure on this view" → measure.jsx (view-bound)
         → pick primitive card → form → preview → YAML
         → [Register measure] OR [Use in derived metric]
                  → formula.jsx → templates or custom → Mode toggle → [Register derived metric]
                          → register.jsx → diff preview → PR metadata → status timeline → live
```

---

## 5. Screen specs

### 5.1 `home.jsx` — NEW (view picker)

Vertical stack of view cards, grouped by job-to-be-done. Source: `cube/model/views/user_360.yml`.

**Groups:**
- **One user at a time:** `user_profile` / `user_activity_timeline` / `user_recharge_timeline` / `user_transactions`
- **Cohorts & audiences:** `user_audience`
- **Time-series metrics:** `revenue_metrics` / `activity_metrics`

**Each card:** view name (mono) + display title + 1-line desc + **freshness chip** (from Cube `refresh_key`) + **grain badge** (transaction/user-day/user-lifetime) + measure count + source-event count + `[Open]` → `view.jsx?view=<name>`.

**Empty state:** "No views yet. Ask a data engineer to define a Cube view, or browse raw events."

### 5.2 `view.jsx` — NEW (per-view detail, drill-down host)

**Header.** Breadcrumb + view title + 1-line desc + freshness chip + grain badge + measure count + source-event count + `[Define a measure on this view]` CTA.

**Tabs:**
- **Measures** (default) — table: name, type, unit, freshness, "Used in N derived metrics", "View YAML".
- **Source events** — list of joined cubes. Click row → events.jsx drawer scoped to that event.
- **Lineage** — bidirectional. Upstream: joined cubes + join keys. Downstream: derived metrics built on this view's measures.

### 5.3 `events.jsx` — modify (now a drill-down, not top-nav)

Two-pane split: event list (left) + event detail (right). Inline pencil → **"Rich edit" button → drawer overlay**.

**Event row additions:**
- Owner avatar (18px monogram).
- Compliance badge (`✓ verified / ⚠ incomplete / ⛔ deprecated`).
- Provenance dot stays.

**Drawer (480px, slide-from-right) — 3 tabs:**

- **Metadata** — display name, description (280-char counter), owner dropdown, domain chip (Monetization/Engagement/Retention/Acquisition/Other), tier radio (Core/Secondary/Exploratory), verified toggle (auto-flips when 4 required fields set), tags.
- **Properties** — 4-column table: type+name / sample / **metadata chips** (`[enum: {…}]` `[PII]` `[suggested measure]`) / actions. Chips clickable: enum → edit list, suggested-measure → routes to measure.jsx pre-bound. "Add property metadata" button below table.
- **Lineage** — bidirectional. Upstream cubes joined + **reachable-via-joins** subsection (from Cube `joins:`, lets PMs see e.g. `mf_users.spend_tier` is reachable from `purchase_completed`). Downstream artifacts (metrics, cohorts, funnels, flows).

**Drawer footer:** "Last edited X ago by Y" + `[Cancel]` `[Save]`. Save flips compliance badge if newly verified.

**Action grid (right pane):** `[Funnel] [Cohort] [Flow] [Define a measure]` (primary). "Metric" entry removed; journey is event → measure → derived metric.

### 5.4 `measure.jsx` — NEW (Layer 1)

**Layout.** Two-pane: left = primitive cards (vertical), right = form + preview + YAML.

**Page head.** `Home / Build / New measure / [event_id chip ×]`. Subhead: "Pick how to aggregate. You'll be able to use this measure in any derived metric, funnel, or cohort." Footer: `[Cancel] [Save draft]` + group `[Register measure]` (primary) | `[Use in derived metric]`.

**9 primitive cards** — each: icon + title + 1-line desc + example hint + **YAML target chip**.

| Card | Description | Example | YAML target |
|---|---|---|---|
| **Sum** | Total of a numeric column. | `sum(amount_local) → 558M` | `measure: sum` |
| **Count** | Rows matching a condition. | `count(purchase_completed) → 18k` | `measure: count` |
| **Unique Count** | Distinct values in a column. | `count_distinct(user_id) → 4,118` | `measure: count_distinct` |
| **Ratio** | One measure divided by another. | `revenue / purchases → 30,690 VND` | `measure: number` |
| **Derived Ratio** | Ratio from two columns in same table. | `SUM(usd)/SUM(local) → 0.000041` | `measure: number` |
| **Times per user** | Per-user agg → across-user agg. | `avg of count(events) per user → 3.4` | `pre_aggregations:` + `measure: number` |
| **Segment** | Reusable boolean filter. | `spend_tier=whale AND country=VN` | `segments:` |
| **Bucket** | Bin a numeric column into bands. | `charged_value → {<10K, …, ≥1M}` | `dimension: case:` |
| **Custom SQL** *(Expert)* | Arbitrary SQL for the `sql:` field. | `SUM(amt) FILTER (WHERE …)` | `measure:` w/ raw `sql:` |

Selected card: 4px orange left border, light tint, bold title.

**Right pane — varies by primitive:**

- **Sum / Count / Unique Count:** column picker (Sum, Unique Count only) + `<FilterBuilder />`.
- **Ratio:** numerator measure dropdown + denominator measure dropdown.
- **Derived Ratio:** numerator column + denominator column + filter; auto-wraps `NULLIF(SUM(denom), 0)`.
- **Times per user:** inner-agg radio (Count/Sum/Unique) + (column picker if Sum/Unique) + outer-agg radio (Avg/Median/P95/Max/Min) + filter on inner. YAML shows `pre_aggregations:` block grouped by `user_id` + a `measure: type: number` reading from it. Info badge: "Builds a Cube pre-aggregation. First build runs after PR merge (< 10 min for ≤ 10M rows)."
- **Segment:** filter rows AND-ed; `[+ OR group]` for OR; optional auto-name (`vn_whales` from `country=VN AND spend_tier=whale`).
- **Bucket:** numeric column + ordered breakpoints + per-band labels (auto-derived, editable). Live preview = horizontal bar list of row counts per band.
- **Custom SQL (Expert):** raw SQL textarea (mono, syntax-highlighted) + unit + name + description. Red warning: "Advanced — your SQL is interpolated into a Cube `measure.sql` field. Verify the YAML preview before submit." Cube YAML preview linted on blur.

**Always-on form sections (below primitive inputs):**

- **Identification:** name (auto-filled, editable), ID (mono, read-only, derived from name), description (280-char), unit pill (Currency/Count/Ratio/Duration/Other, auto-detected, overridable).
- **Preview:** big number + sub-label + 14-point sparkline + ProvFooter (grain / source / ms / dot).
- **YAML preview** (collapsed accordion): syntax-highlighted, copy button.

**States:** no event/view bound → slim picker modal; Ratio with no measures yet → empty dropdown w/ "Switch to Derived Ratio" chip; Times-per-user → pre-agg commitment badge; Custom SQL → red warning if YAML lint preflight fails.

### 5.5 `formula.jsx` — modify (Layer 2 — derived metric)

Top tab bar: `[Templates]` `[Custom formula ●]` (default-active for now).

**Templates tab:** 2×3 card grid. Cards: Daily Active Users / Conversion rate / Retention curve / Funnel / Cohort overlap / Rate of change. Each: icon + title + 1-line + "Fill template" chip → auto-fills inputs A/B/C and formula → switches to Custom formula tab.

**Custom formula tab:**
- Inputs A/B/C cards (existing pattern preserved). Measure dropdown populated from `MC_DATA.registrations[kind='measure']`. Inline `+ New measure` link routes to measure.jsx, returns pre-bound.
- Formula bar + operators (`+ − × ÷ ( ) %`) + cursor-aware insert (existing).
- Templates dropdown next to operators is **removed** (moved to top tab).

**Mode toggle (callout band above register footer):**

```
Is this a derived metric or a property?

◉ Derived metric — one number per query, charted, registered as
                   `measure: type: number` on a Cube view.

○ Property — computed per-event or per-user; registered as a
            `dimension:` and surfaced as a feature in the feature store.

Pick one. This decides which YAML block we emit on register.
```

Pre-register guard: if Mode unset, `[Register derived metric]` disabled with tooltip.

### 5.6 `register.jsx` — modify (PR-based)

**Entry badge** (top, was previously single-kind): `[Measure]` / `[Derived metric]` / `[Property]` + name + ID.

**"What this becomes" panel** (mono card above YAML) — copy varies by kind:
- Measure (atomic): "→ `measure:` block in `cube/model/cubes/<source>.yml`. Cube reloads on merge."
- Measure (Times-per-user): "→ `pre_aggregations:` grouped by `user_id` + a `measure: type: number`. First build runs on merge."
- Measure (Segment): "→ `segments:` block in `cube/model/cubes/<source>.yml`."
- Measure (Bucket): "→ `dimension.case:` block in `cube/model/cubes/<source>.yml`."
- Measure (Custom SQL): "→ `measure:` with raw `sql:` in `cube/model/cubes/<source>.yml`. CI runs Cube lint; manual review required."
- Derived metric: "→ `measure: type: number` on `cube/model/views/<view>.yml`. Feature-store registration follows."
- Property: "→ `dimension:` block (per-event on source cube, or per-user on `mf_users`) + feature-store feature."

**PII inheritance callout** (if any input has `public: false`): "Private inputs detected. Measure `X` depends on PII property `Y`. The registered entry inherits `public: false`."

**Similar-entries block:** real similarity (substring match on formula / column / filter) within same kind. Each match: name, ID, 1-line desc, "View" link.

**Submit — 3-step modal:**

1. **Diff preview** — two-column (current YAML | proposed YAML) for the target file. `[Cancel] [Looks good →]`.
2. **PR metadata** — title (auto), body (auto from desc + use-case + "What this becomes"), reviewer (required dropdown), branch (read-only auto), labels (auto: `catalogue`, kind, source cube). `[Cancel] [Open PR]`.
3. **Status & wait** — 5-node horizontal timeline `draft → in_review → approved → materializing → live`. PR URL chip at top. Each node: dot + label + timestamp. Stalled > 24h shows `⚠ Stalled` + "Ping reviewer" / "Re-run service". Final actions in `live`: `[View in library]` `[Build on this]` `[Done]`.

**Failure states:** Service unhealthy → red banner, retries every 5min, logs link. CI failed → `⛔ CI failed` on `in_review` with inline workflow output. PR rejected → "PR closed without merge" + reviewer comment + `[Edit and resubmit]`.

---

## 6. Components (specs in one table)

| Component | Where | Key props | Notes |
|---|---|---|---|
| `<PrimitiveCard />` | measure.jsx | `icon, title, description, exampleHint, yamlTarget, selected, onClick` | 4px orange left border when selected |
| `<MetadataDrawer />` | events.jsx | `event, open, onClose, onSave` | 480px right slide; 3 tabs; sticky footer |
| `<PropertyChip />` | events.jsx Properties | `kind, value, onClick?` | kinds: enum/pii/suggested-measure/deprecated |
| `<ComplianceBadge />` | events.jsx row | `status, missingFields?, onFix?` | verified/incomplete/deprecated; hover tooltip |
| `<FilterBuilder />` | measure.jsx forms | `properties, value, onChange` | Operators: `= ≠ > < ≥ ≤ in not in is null is not null` **+ relative-window** (today / yesterday / last 7d / last 30d / this month / previous month / custom range) |
| `<DateRangePicker />` *(new)* | inside FilterBuilder | `value, onChange, presets` | Calendar; opens when "custom range" operator selected |
| `<YamlPreview />` | measure / register.jsx | `yaml, collapsed?` | Syntax highlight via existing `colorize`; copy button |
| `<TemplateCard />` | formula.jsx Templates | `icon, title, description, onPick` | Grid layout |
| `<ModeCallout />` | formula.jsx | `value: 'derived-metric'\|'property', onChange` | Prominent band above register footer |
| `<FreshnessChip />` | home / view / preview | `refreshEvery, lastUpdatedAt?` | From Cube `refresh_key.every` |
| `<GrainBadge />` | home / view / event row | `grain, customLabel?` | transaction/user-day/user-lifetime/session/custom; color-coded |
| `<PrDiffPreview />` | register step 1 | `currentYaml, proposedYaml, filePath` | Full-screen modal, two-column diff |
| `<PrSubmitForm />` | register step 2 | `defaultTitle, defaultBody, defaultBranch, defaultLabels, reviewers, onSubmit` | Reviewer required |
| `<PrStatusTimeline />` | register step 3 | `prUrl, state, nodeTimestamps, lastError?` | 5-node horizontal timeline |
| `<ReachableProperties />` | events.jsx Lineage | `event, joins` | Lists `<cube>.<property>` reachable via `joins:` |
| `<PiiInheritBadge />` | Library + register | `reason` | Amber lock pill; tooltip shows dependency chain |

---

## 7. Interaction patterns

- **Drawer-from-row.** Click row → right pane. Click "Rich edit" → drawer overlay. Esc closes drawer.
- **Card grid selection.** Switching primitive cards preserves per-card form state.
- **Tab state.** formula.jsx Templates → fill → auto-switch to Custom formula; user can return.
- **Live preview latency.** 220ms fade-in (mock data lands in < 100ms).
- **YAML copy.** Toast "Copied" near YAML block, 1.5s.
- **Route-and-return.** Property chip → measure.jsx → `[Cancel]` returns to events.jsx with drawer reopened at Properties tab.
- **Compliance recompute.** Save in drawer → recompute badge on row immediately; brief checkmark microanimation on flip-to-verified.

---

## 8. Copy & microcopy

Tone: direct, terse, no marketing voice. Imperative for CTAs. Periods at end.

| Surface | Copy |
|---|---|
| Drawer empty description | "Describe what triggers this event. Examples below." |
| Compliance tooltip (incomplete) | "Missing: description, owner, domain. Click to fix." |
| Compliance tooltip (verified) | "Verified by Khoi · 2 days ago." |
| measure.jsx subhead | "Pick how to aggregate. You'll be able to use this measure in any derived metric, funnel, or cohort." |
| Times-per-user commitment | "Builds a Cube pre-aggregation grouped by `user_id`. First build runs after PR merge (< 10 min for ≤ 10M rows)." |
| Custom SQL warning | "Advanced — your SQL is interpolated into a Cube `measure.sql` field. Verify the YAML preview before submit." |
| Mode callout instruction | "Pick one. This decides which YAML block we emit on register." |
| Register PII callout | "Private inputs detected. The registered entry will not appear in the public Catalogue API." |
| Save measure success | "Measure registered. View in library or build a derived metric using this." |
| Stalled PR | "Stalled > 24h. Ping reviewer or re-run service." |
| Empty events search | "No events match `<query>`. Try a shorter term or remove the active-only filter." |
| Empty similar-entries | "No similar entries found. This one is novel." |

---

## 9. Data shape (`data.js`)

```js
// views (NEW — top-level for view-first home)
views: [{
  name, title, description, sourceCubes: [], grain,         // transaction|user-day|user-lifetime|session
  refreshEvery, lastRefreshedAt,                            // from Cube refresh_key
  group,                                                    // one-user|cohorts|time-series
  measureCount, sourceEventCount, jobToBeDone
}]

// events — append fields
{
  // existing fields…
  owner, domain, tier, verified, tags, displayName,
  sourceCube, grain, refreshEvery,                          // NEW — link back to Cube YAML
  properties: [{ name, type, sample, enum, pii, suggestedMeasure, deprecated }],
  reachableProperties: [{ via, property, joinKey }],        // NEW — from Cube joins:
  usedIn: [...],                                            // downstream
  usedBy: [...],                                            // NEW — upstream views containing this event
}

// registrations (NEW — replaces session-local userMeasures)
registrations: [{
  id, kind,                                                 // measure|derived-metric|property|segment|bucket|custom-sql
  name, desc,
  // measure-specific
  primitive, column, event, sourceCube, filters, unit, rawSql?,
  // derived-metric specific
  formula, inputs, mode, targetView,
  // PR + service state
  pr: { url, number, branch, reviewer, filePath },
  state,                                                    // draft|in_review|approved|materializing|live|stalled|rejected|ci_failed
  stateHistory: [{ state, at }],
  yaml, public, createdAt
}]

// templates — 6 entries for formula.jsx Templates tab
templates: [{ id, title, description, icon, formula, inputDefaults }]

// users (NEW — owner picker source)
users: [{ id, name, team, avatarInitials }]
```

In-memory only for v2.0 prototype. Real backend (PR flow + service) is a separate engineering track.

---

## 10. Out of scope (v2.0)

- Live data; prototype runs on `MC_DATA`.
- Real Cube SQL execution; previews are deterministic fake numbers from `event.volume`.
- AI / NL-to-metric input.
- Drag-and-drop visual pipeline.
- Multi-user collaboration / comments.
- Revision history (placeholder line in drawer is fine).
- Library v2 split (per-kind tabs) — v2.1.
- PR-flow backend wiring (`gh pr create`, `catalogue-materializer`). UI runs against `MC_DATA.registrations` mock.
- YAML round-trip back to UI state.
- Mobile / responsive < 1024px.

---

## 11. Acceptance criteria

A PM can, in one session, with zero help from a data engineer:

1. Land on `home.jsx`. Pick view `revenue_metrics`.
2. Land on `view.jsx`. See freshness chip, grain badge, measures tab, source events tab.
3. Open Source events tab → click `purchase_completed`. Drawer opens. Fill description / owner / domain / tier. Save → compliance badge flips `✓ verified`.
4. Click `[Define a measure]`.
5. Land on `measure.jsx` with `purchase_completed` + `recharge` pre-bound.
6. Pick **Sum**, choose `amount_local`, add filter `currency = VND`. See live preview, auto-name `Purchase Revenue (local)`, YAML emits `measure: sum`.
7. `[Use in derived metric]` → register PR flow runs → on `live`, route to `formula.jsx` with new measure in input A.
8. Switch to **Templates** tab → pick **Conversion rate**. Auto-fill formula. Switch back → tweak.
9. Pick Mode = **Derived metric** (not "Metric") in callout.
10. `[Register derived metric]` → 3-step modal: diff preview → PR metadata → timeline `draft → in_review → approved → materializing → live`. PR URL visible throughout.
11. Land in Library. Both entries visible with correct badges (`[Measure]` / `[Derived metric]`).

**Additional flows that must work:**

12. **Segment** primitive on `mf_users` (e.g. `spend_tier=whale AND country=VN`) → `segments:` PR.
13. **Bucket** primitive on `revenue_vnd` with breakpoints `[10000, 50000, 200000, 1000000]` → `dimension.case:` PR.
14. **Times per user** measure (inner: count(`purchase_completed`); outer: avg) → `pre_aggregations:` PR; materialization step takes longer; badge sets expectation.
15. **Custom SQL** card (Expert) → raw SQL textarea → YAML lint passes → submit.
16. **Relative-time filter** (`log_date last 30 days`) inside Sum/Count → emits a measure-local `filters:` block.
17. **PII property** → Library entry has "private" badge; register form shows callout.

**Failure modes:** any hidden menu, dropdown > 2 deep, jumping to a different nav section to find a primitive, or wrong vocabulary ("metric" where it should be "measure" or "derived metric") = design has missed.

---

## 12. Visual references

- Statsig metric types — card grid (https://docs.statsig.com/metrics/metric-types/)
- Mixpanel Lexicon — drawer pattern (https://docs.mixpanel.com/docs/data-governance/lexicon)
- Amplitude Data Govern — tier / owner / verified
- Looker calculations — formula bar reference
- Reference codebase: `plans/reports/reference/Metrics-Catalogue/screens/`

---

## 13. Open questions

1. **Owner picker source.** Tentative: `MC_DATA.users` mock for prototype.
2. **Filter values UX.** Tentative: enum-aware if `property.enum` set, free text otherwise.
3. **Library v2 structure.** One surface with kind badges, or tabs per kind? Affects v2.1.
4. **Verified trigger.** Auto-flip on 4 required fields, with manual override? Leading option.
5. **PR target — cube vs view.** Atomic measures live on source cube. Derived metrics: cube or view? Cube convention says **view** — confirm with DE.
6. **`catalogue-materializer` service identity.** Existing service or build thin one? UI only needs status webhook contract.
7. **Branch protection on `cube/model/`.** Base = `main` or `cube/staging`?
8. **Service-account permissions for `gh pr create`.** Bot identity / reviewer assignment / label perms.
9. **Reviewer routing.** Per-domain (Monetization → Revenue team), with PM override?
10. **Segment scope.** Segment defined on `mf_users` reusable across joining cubes; picker should resolve via Cube `joins:`.
11. **Custom SQL gating.** Expert toggle in v2.0, or hide until v2.1? Recommend Expert toggle now — low cost, high power-PM value.

---

**Status:** READY-TO-PASTE. Companion: `researcher-260514-1547-event-semantics-and-metric-builder-ux.md`.
