# Design PRD: Metrics Catalogue v2 — Event Semantics + Three-Layer Metric Authoring

**Audience:** Claude Design (paste-ready)
**Companion research:** `researcher-260514-1547-event-semantics-and-metric-builder-ux.md`
**Backup (full):** `prd-260514-1559-metrics-catalogue-redesign-backup.md` (1,017 lines)
**Codebase:** `plans/reports/reference/Metrics-Catalogue/` — single-page React-on-CDN, JSX edits only, custom design system
**Date:** 2026-05-14 17:17 — expanded summary (mid-detail between 400-line summary and 1,017-line backup)

---

## 1. Problem & job-to-be-done

A non-tech PM sits in front of raw events on a Cube semantic layer over Trino. Job: **understand the data → validate a hypothesis → mint a new metric** that the data pipeline materializes and serves through a feature store.

**v1 demo gaps:**

- Semantic enrichment is shallow (description-only).
- Formula bar floats above a hardcoded measure list — a PM cannot mint a new measure from a raw event.
- Vocabulary collapses "measure" and "metric" into one ambiguous label.
- "Register" button is a stub.
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
    └── Funnel / Cohort / Flow / Retention (unchanged)
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

Vertical stack of view cards grouped by job-to-be-done. Source: `cube/model/views/user_360.yml`.

**Groups & cards:**

- **One user at a time:** `user_profile` / `user_activity_timeline` / `user_recharge_timeline` / `user_transactions`
- **Cohorts & audiences:** `user_audience`
- **Time-series metrics:** `revenue_metrics` / `activity_metrics`

**Card anatomy:**

```
┌─────────────────────────────────────────────────┐
│ revenue_metrics                       [Open →] │
│ Revenue time-series                             │
│ Daily/monthly recharge revenue and ARPPU,       │
│ sliced by country, OS, payment channel.         │
│ ─────────────────────────────────────────────── │
│ ● fresh · 30m   ⬢ grain: user-day               │
│ 4 measures · 2 source events                    │
└─────────────────────────────────────────────────┘
```

- View name (mono, 14px) + display title (16px, semibold) + 1-line description (13px muted)
- **Freshness chip** — from Cube `refresh_key.every`. Green dot if last build < 1 freshness window, amber otherwise.
- **Grain badge** — `transaction` / `user-day` / `user-lifetime` / `session`. Color-coded.
- Measure count · source-event count.
- `[Open]` → `view.jsx?view=<name>`.

**Empty state:** "No views yet. Ask a data engineer to define a Cube view, or browse raw events."

---

### 5.2 `view.jsx` — NEW (per-view detail, drill-down host)

**Header:**

```
Home / Explore / Views / revenue_metrics
─────────────────────────────────────────────────
revenue_metrics                                  [Define a measure on this view]
Revenue time-series — daily/monthly recharge revenue and ARPPU.
● fresh · 30m   ⬢ grain: user-day   4 measures · 2 source events
─────────────────────────────────────────────────
```

**Tabs:**

- **Measures** (default) — table: `name | type | unit | freshness | used in N derived metrics | view YAML`. Click row → preview drawer.
- **Source events** — list of joined cubes. Click row → opens events.jsx drawer scoped to that event.
- **Lineage** — bidirectional. Upstream: joined cubes + join keys. Downstream: derived metrics built on this view's measures.

---

### 5.3 `events.jsx` — modify (now a drill-down, not top-nav)

Two-pane split: event list (left) + event detail (right). Inline pencil → **"Rich edit" button → drawer overlay**.

**Event row additions (left pane):**

```
┌─────────────────────────────────────────────────────────────────────┐
│ ● purchase_completed                       KT  ✓ verified         ▸ │
│   ─ 18k/day · 14 reports                                             │
└─────────────────────────────────────────────────────────────────────┘
  prov   event id                            owner  compliance    expand
```

- **Owner avatar** — 18px monogram (e.g. `KT`). Defaults to `?` gray when unset. Tooltip: "Owner: Khoi Tran (Data team)" or "No owner — click to assign".
- **Compliance badge** — `✓ verified` (green outline, all 4 required fields filled) / `⚠ incomplete` (amber, hover shows missing fields + Fix link) / `⛔ deprecated` (gray strikethrough).
- Provenance dot stays — orthogonal axis (data source maturity).

**Drawer (480px slide-from-right) — 3 tabs:**

```
                                       ┌──────────────────────────────┐
                                       │ purchase_completed         × │
                                       ├──────────────────────────────┤
                                       │ [Metadata][Properties][Lin.] │
                                       ├──────────────────────────────┤
                                       │ Display name                 │
                                       │ [ User Purchase            ] │
                                       │ Description (45/280)         │
                                       │ ┌──────────────────────────┐ │
                                       │ │ Fires when a user…       │ │
                                       │ └──────────────────────────┘ │
                                       │ Owner   [Khoi Tran        ▾] │
                                       │ Domain  [Monetization     ▾] │
                                       │ Tier    ◉ Core ○ Sec ○ Exp   │
                                       │ ✓ Verified                   │
                                       ├──────────────────────────────┤
                                       │ Last edited 3d ago    [Save] │
                                       └──────────────────────────────┘
```

- **Metadata.** Display name (distinct from technical `event.id`), description (280-char counter), owner dropdown, domain chip group (Monetization / Engagement / Retention / Acquisition / Other), tier radio (Core / Secondary / Exploratory, with inline gloss), verified toggle (auto-flips when 4 required fields set; manual override allowed), tags (free-text chips).
- **Properties.** 4-column table: `[type-icon + name] | [sample] | [metadata chips] | [actions]`. Metadata chips: `[enum: {VND, USD, THB}]` (click to edit enum list), `[PII]` (amber + lock), `[suggested measure: sum(amount_local)]` (clickable → measure.jsx pre-bound), `[deprecated]` (gray). `[+ Add property metadata]` button below table.
- **Lineage.** Bidirectional.
  - Upstream — joined cubes + a **"Reachable via joins"** subsection sourced from Cube `joins:` blocks (e.g. tells PM that `purchase_completed` rows can be sliced by `mf_users.spend_tier` via the `account_id = user_id` join).
  - Downstream — chips: metrics / cohorts / funnels / flows consuming this event.
  - Empty downstream state: "No artifacts use this event yet. Define a measure to start."

**Drawer footer:** "Last edited X ago by Y" + `[Cancel]` `[Save]`. Save flips compliance badge if newly verified — brief checkmark microanimation.

**Action grid (right pane, replacing today's quad):** `[Funnel]` `[Cohort]` `[Flow]` `[Define a measure]` (primary, orange). "Metric" entry removed — journey is now event → measure → derived metric, never event → metric directly.

---

### 5.4 `measure.jsx` — NEW (Layer 1 — primitive picker)

**Layout.** Two-pane:

```
Home / Build / New measure / [purchase_completed ×]
─────────────────────────────────────────────────────────────────────────────
Define a measure on  purchase_completed
Pick how to aggregate. You'll be able to use this measure in any derived
metric, funnel, or cohort.
─────────────────────────────────────────────────────────────────────────────
                                       [Cancel]  [Save draft]  [Register]
─────────────────────────────────────────────────────────────────────────────

┌─ PRIMITIVES ───────────┐   ┌─ INPUTS ──────────────────────────────────┐
│ ● Sum                  │   │ Column                                    │
│   Total of numeric col │   │ [ amount_local                          ▾]│
│   sum(amt) → 558M      │   │ sample: 50,000                            │
├────────────────────────┤   │                                           │
│ ○ Count                │   │ Filter (optional)               [+ Add]   │
├────────────────────────┤   │   currency  [= ▾]  [VND]            [×]  │
│ ○ Unique Count         │   ├───────────────────────────────────────────┤
├────────────────────────┤   │ Identification                            │
│ ○ Ratio                │   │ Name [ Purchase Revenue (local)         ] │
├────────────────────────┤   │ ID   purchase_revenue_local               │
│ ○ Derived Ratio        │   │ Desc [ Total amount_local across…       ] │
├────────────────────────┤   │ Unit [Currency ▾]                         │
│ ○ Times per user       │   └───────────────────────────────────────────┘
├────────────────────────┤
│ ○ Segment              │   ┌─ PREVIEW ─────────────────────────────────┐
├────────────────────────┤   │     558,920,000                            │
│ ○ Bucket               │   │     VND                                    │
├────────────────────────┤   │     ╱╲    ╱╲                               │
│ ○ Custom SQL (Expert)  │   │  ╱╲╱  ╲╱╲╱  ╲╱╲   last 14 days            │
└────────────────────────┘   │  ● cube: recharge · 312ms                  │
                             └────────────────────────────────────────────┘

                             ▾ Cube YAML preview
```

**The 9 primitive cards — each: icon + title + 1-line + example hint + YAML target chip.**

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
| **Custom SQL (Expert)** | Arbitrary SQL for the `sql:` field. | `SUM(amt) FILTER (WHERE …)` | `measure:` w/ raw `sql:` |

Selected card: 4px orange left border, light tint, bold title.

**Right pane — primitive-specific form (always followed by Identification / Preview / YAML):**

- **Sum / Count / Unique Count.** Sum + Unique Count have a column picker (type-ahead, shows sample value); Count has none. All three have `<FilterBuilder />`. Unique Count defaults dedupe column to `user_id` if present; toggle "approx (fast, ~1.6% error)" → emits `count_distinct_approx`.
- **Ratio.** Numerator measure dropdown + denominator measure dropdown — both populated from `MC_DATA.registrations[kind='measure']`. Inline math preview: `<num_value> / <denom_value> = <result>`.
- **Derived Ratio.** Numerator column + denominator column (numeric) + filter rows. YAML auto-wraps `NULLIF(SUM(denom), 0)`.
- **Times per user.** Inner-agg radio (Count of events / Sum of column / Unique count of column) + (column picker if Sum/Unique) + outer-agg radio (Avg / Median / P95 / Max / Min) + filter on inner. YAML preview shows `pre_aggregations:` block grouped by `user_id` followed by a `measure: type: number` reading from the pre-agg. Info badge near YAML: "Builds a Cube pre-aggregation. First build runs after PR merge (< 10 min for ≤ 10M rows)."
- **Segment.** Filter rows AND-ed; `[+ OR group]` for OR; optional auto-name (`vn_whales` from `country=VN AND spend_tier=whale`).
- **Bucket.** Numeric column + ordered breakpoints (e.g. `10000, 50000, 200000, 1000000`) + per-band labels (auto-derived: `< 10K / 10K–50K / 50K–200K / 200K–1M / ≥ 1M`, editable). Live preview = horizontal bar list of row counts per band.
- **Custom SQL (Expert).** Raw SQL textarea (mono, syntax-highlighted) + unit + name + description. Red warning: "Advanced — your SQL is interpolated into a Cube `measure.sql` field. Verify the YAML preview before submit." Cube YAML preview linted on blur (pre-flight against a tiny `cube validate`).

**Always-on form sections:**

- **Identification.** Name (auto-filled, editable — e.g. `Sum of amount_local on purchase_completed`), ID (mono, read-only, derived from name via snake-case), description (280-char counter, pre-filled from primitive + column), unit pill (Currency / Count / Ratio / Duration / Other — auto-detected, overridable).
- **Preview.** Big number (live evaluated against mock — for prototype, deterministic from `event.volume`), sub-label (unit), 14-point sparkline (reuse `formula.jsx` pattern), `ProvFooter` (grain / source / ms / dot).
- **YAML preview** (collapsed accordion). Syntax-highlighted via existing `colorize`. Copy button (toast 1.5s).

**Footer CTAs:** `[Cancel]` / `[Save draft]` / group `[Register measure]` (primary, opens PR flow) | `[Use in derived metric]` (registers AND routes to formula.jsx pre-bound as input A).

**States:**

- No event/view bound → slim event-picker modal first.
- Ratio with no measures yet → empty dropdown w/ inline "No measures yet. Define a Sum or Count first." + chip "Switch to Derived Ratio".
- Times-per-user → pre-agg commitment badge visible.
- Custom SQL → red warning if YAML lint preflight fails; submit disabled.

---

### 5.5 `formula.jsx` — modify (Layer 2 — derived metric)

**Page head:**

```
Home / Build / New derived metric
─────────────────────────────────────────────────────────────────────────────
Whale 7-day Recharge Rate                whale_recharge_rate_7d
─────────────────────────────────────────────────────────────────────────────
[Discard]                          [Save draft]   [Register derived metric]

┌────────────┬──────────────────┐
│ Templates  │ Custom formula ● │
└────────────┴──────────────────┘
```

**Templates tab.** 2×3 card grid:

- **Daily Active Users** — `count_distinct(user_id) where event_name in (selected events)`
- **Conversion rate** — `count_distinct(users_did_B) / count_distinct(users_did_A)`
- **Retention curve** — D1 / D7 / D30; user picks reference + return event
- **Funnel** — multi-step event chain with conversion at each step
- **Cohort overlap** — % of cohort A who also belong to cohort B
- **Rate of change** — `(this_week - last_week) / last_week`

Each card: icon + title + 1-line desc + "Fill template" chip → auto-fills inputs A/B/C + formula → switches to **Custom formula** tab so PM can review/tweak.

**Custom formula tab.** Existing demo block, plus:

- A/B/C input cards (existing). Measure picker dropdown now populated from `MC_DATA.registrations[kind='measure']`. Inline `[+ New measure]` link → measure.jsx, returns pre-bound.
- Formula bar + operators (`+ − × ÷ ( ) %`) + cursor-aware insert (preserve existing).
- Templates dropdown next to operators is **removed** (now lives in the top tab).

**Mode toggle (callout band above register footer):**

```
┌────────────────────────────────────────────────────────────────────┐
│  Is this a derived metric or a property?                           │
│                                                                    │
│  ◉ Derived metric — one number per query, charted, registered      │
│                     as `measure: type: number` on a Cube view.    │
│                                                                    │
│  ○ Property — computed per-event or per-user; registered as a     │
│              `dimension:` and surfaced as a feature in the         │
│              feature store.                                        │
│                                                                    │
│  Pick one. This decides which YAML block we emit on register.     │
└────────────────────────────────────────────────────────────────────┘
```

Pre-register guard: if Mode unset, `[Register derived metric]` disabled with tooltip.

**Empty-entry state** (no input seeded): top banner: "Tip: define a measure first if your primitive is a sum / count / unique count. Otherwise pick a template." with chips `[Define a measure]` `[Browse templates]`.

---

### 5.6 `register.jsx` — modify (PR-based handoff)

**Entry badge** (top): `[Measure]` / `[Derived metric]` / `[Property]` + name + ID (mono).

**"What this becomes" panel** (mono card above YAML) — copy varies by kind:

- Measure (atomic): "→ `measure:` block in `cube/model/cubes/<source>.yml`. Cube reloads on merge."
- Measure (Times-per-user): "→ `pre_aggregations:` grouped by `user_id` + a `measure: type: number`. First build runs on merge."
- Measure (Segment): "→ `segments:` block in `cube/model/cubes/<source>.yml`."
- Measure (Bucket): "→ `dimension.case:` block in `cube/model/cubes/<source>.yml`."
- Measure (Custom SQL): "→ `measure:` with raw `sql:` in `cube/model/cubes/<source>.yml`. CI runs Cube lint; manual review required."
- Derived metric: "→ `measure: type: number` on `cube/model/views/<view>.yml`. Feature-store registration follows."
- Property: "→ `dimension:` block (per-event on source cube, or per-user on `mf_users`) + feature-store feature."

**PII inheritance callout** (if any input has `public: false`): "Private inputs detected. Measure `X` depends on PII property `Y`. The registered entry inherits `public: false`."

**Similar-entries block.** Real similarity (substring on formula / column / filter) within same kind. Each match: name, ID, 1-line desc, "View" link. Empty: "No similar entries found. This one is novel."

**Submit — 3-step modal:**

1. **Diff preview** — two-column (current YAML | proposed YAML) for the target file. `[Cancel] [Looks good →]`.
2. **PR metadata** — title (auto from name), body (auto from desc + use-case + "What this becomes"), reviewer (required dropdown — domain-routed by default), branch (read-only auto), labels (auto: `catalogue`, kind, source cube). `[Cancel] [Open PR]`.
3. **Status & wait** — 5-node horizontal timeline `draft → in_review → approved → materializing → live`. PR URL chip at top (opens in new tab). Each node: dot + label + timestamp. Stalled > 24h shows `⚠ Stalled` + "Ping reviewer" / "Re-run service". Final actions in `live`: `[View in library]` `[Build on this]` `[Done]`.

**Failure states:**

- Service unhealthy → red banner, retries every 5 min, logs link.
- CI failed → `⛔ CI failed` on `in_review` with inline workflow output.
- PR rejected → "PR closed without merge" + reviewer comment + `[Edit and resubmit]`.

---

## 6. Components (specs in one table)

| Component | Where | Key props | Notes |
|---|---|---|---|
| `<PrimitiveCard />` | measure.jsx | `icon, title, description, exampleHint, yamlTarget, selected, onClick` | 4px orange left border when selected |
| `<MetadataDrawer />` | events.jsx | `event, open, onClose, onSave` | 480px right slide; 3 tabs; sticky footer |
| `<PropertyChip />` | events.jsx Properties | `kind, value, onClick?` | kinds: `enum / pii / suggested-measure / deprecated` |
| `<ComplianceBadge />` | events.jsx row | `status, missingFields?, onFix?` | verified / incomplete / deprecated; hover tooltip with missing fields |
| `<FilterBuilder />` | measure.jsx forms | `properties, value, onChange` | Operators: `= ≠ > < ≥ ≤ in not in is null is not null` **+ relative-window** (today / yesterday / last 7d / last 30d / this month / previous month / custom range) |
| `<DateRangePicker />` *(new)* | inside FilterBuilder | `value, onChange, presets` | Calendar; opens when "custom range" operator selected |
| `<YamlPreview />` | measure / register.jsx | `yaml, collapsed?` | Syntax highlight via existing `colorize`; copy button |
| `<TemplateCard />` | formula.jsx Templates | `icon, title, description, onPick` | Grid layout; "Fill template" chip CTA |
| `<ModeCallout />` | formula.jsx | `value: 'derived-metric' \| 'property', onChange` | Prominent band above register footer |
| `<FreshnessChip />` | home / view / preview | `refreshEvery, lastUpdatedAt?` | From Cube `refresh_key.every` |
| `<GrainBadge />` | home / view / event row | `grain, customLabel?` | `transaction / user-day / user-lifetime / session / custom`; color-coded |
| `<PrDiffPreview />` | register step 1 | `currentYaml, proposedYaml, filePath` | Full-screen modal, two-column diff |
| `<PrSubmitForm />` | register step 2 | `defaultTitle, defaultBody, defaultBranch, defaultLabels, reviewers, onSubmit` | Reviewer required |
| `<PrStatusTimeline />` | register step 3 | `prUrl, state, nodeTimestamps, lastError?` | 5-node horizontal timeline |
| `<ReachableProperties />` | events.jsx Lineage | `event, joins` | Lists `<cube>.<property>` reachable via Cube `joins:` |
| `<PiiInheritBadge />` | Library + register | `reason` | Amber lock pill; tooltip shows dependency chain |

---

## 7. Interaction patterns

- **Drawer-from-row.** Click row → right pane. Click "Rich edit" → drawer overlay. Esc closes drawer.
- **Card grid selection.** Switching primitive cards in measure.jsx preserves per-card form state (so PM doesn't lose typing).
- **Tab state.** formula.jsx Templates → fill → auto-switch to Custom formula; tab state preserved on return.
- **Live preview latency.** 220ms fade-in (mock data lands in < 100ms).
- **YAML copy.** Toast "Copied" near YAML block, 1.5s.
- **Route-and-return.** Property chip in events.jsx Properties → routes to measure.jsx with primitive + column pre-bound. `[Cancel]` returns to events.jsx with drawer reopened at Properties tab.
- **Compliance recompute.** Save in drawer → recompute badge on row immediately; brief checkmark microanimation on flip-to-verified.
- **PR status polling.** register step 3 polls every 10s. On `live`, plays a subtle success chime + confetti microanimation (single burst).

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
| Save measure success toast | "Measure registered. View in library or build a derived metric using this." |
| Stalled PR | "Stalled > 24h. Ping reviewer or re-run service." |
| Empty events search | "No events match `<query>`. Try a shorter term or remove the active-only filter." |
| Empty similar-entries | "No similar entries found. This one is novel." |
| Empty lineage downstream | "No artifacts use this event yet. Define a measure to start." |
| Diff preview header | "About to open a pull request against `cube/model/cubes/<source>.yml`." |
| Live state final action | "Live in the catalogue. View in library or build on this." |

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
  // existing fields...
  owner, domain, tier, verified, tags, displayName,
  sourceCube, grain, refreshEvery,                          // NEW — link back to Cube YAML
  properties: [{
    name, type, sample,
    enum,                                                   // null | ["VND","USD","THB"]
    pii,                                                    // boolean
    suggestedMeasure,                                       // { primitive, column } | null
    deprecated
  }],
  reachableProperties: [{ via, property, joinKey }],        // NEW — from Cube joins:
  usedIn: [...],                                            // downstream artifacts
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
3. Open Source events tab → click `purchase_completed`. Drawer opens. Fill description / owner / domain / tier. Save → compliance badge flips `✓ verified` with brief checkmark microanimation.
4. Click `[Define a measure]` in the action grid.
5. Land on `measure.jsx` with `purchase_completed` + `recharge` cube pre-bound.
6. Pick **Sum**, choose `amount_local`, add filter `currency = VND`. See live preview render, auto-name `Purchase Revenue (local)`, YAML emits `measure: sum`.
7. `[Use in derived metric]` → PR flow runs (3-step modal: diff → metadata → timeline) → on `live`, routes to `formula.jsx` with the new measure in input A.
8. Switch to **Templates** tab → pick **Conversion rate**. Auto-fill formula. Switch back to Custom formula → tweak.
9. Pick Mode = **Derived metric** (not "Metric") in callout.
10. `[Register derived metric]` → 3-step modal: diff preview → PR metadata (reviewer required) → timeline `draft → in_review → approved → materializing → live`. PR URL chip visible throughout.
11. Land in Library. Both entries visible with correct badges (`[Measure]` / `[Derived metric]`).

**Additional flows that must work:**

12. **Segment** primitive on `mf_users` (e.g. `spend_tier=whale AND country=VN`) → `segments:` PR.
13. **Bucket** primitive on `revenue_vnd` with breakpoints `[10000, 50000, 200000, 1000000]` → `dimension.case:` PR.
14. **Times per user** measure (inner: count(`purchase_completed`); outer: avg) → `pre_aggregations:` PR; materialization step takes longer; badge sets expectation.
15. **Custom SQL** card (Expert) → raw SQL textarea → YAML lint passes → submit.
16. **Relative-time filter** (`log_date last 30 days`) inside Sum/Count → emits a measure-local `filters:` block.
17. **PII property** → Library entry has "private" badge; register form shows PII inheritance callout.

**Failure modes:** any hidden menu, dropdown > 2 deep, jumping to a different nav section to find a primitive, or wrong vocabulary ("metric" where it should be "measure" or "derived metric") = design has missed.

---

**Status:** READY-TO-PASTE. Companion: `researcher-260514-1547-event-semantics-and-metric-builder-ux.md`.
Backup (full): `prd-260514-1559-metrics-catalogue-redesign-backup.md`.
