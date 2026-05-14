# Design PRD: Metrics Catalogue v2 — Event Semantics + Three-Layer Metric Authoring

**Audience:** Claude Design (paste-ready)
**Companion research:** `researcher-260514-1547-event-semantics-and-metric-builder-ux.md` (with Layer-1 addendum + Resolved-Decisions block 2026-05-14 16:51)
**Codebase:** `plans/reports/reference/Metrics-Catalogue/` — single-page React-on-CDN, JSX edits only, no Next.js, no Tailwind, custom design system already in place
**Date:** 2026-05-14 (patched 2026-05-14 16:51 — Cube-cross-walk decisions)

---

## 0. Patch 2026-05-14 16:51 — what changed since first draft

Four open questions are resolved; PRD body updated to match. Where the body below contradicts this block, this block wins.

1. **Vocabulary split.** "Measure" (Layer 1 — Cube atom, `type: count/sum/...`) and "Derived metric" (Layer 2 — `type: number` over measure refs) are **separate everywhere** in UI labels, library taxonomy, badges, and YAML preview. The umbrella term is "catalogue entry". "Metric" alone never appears.
2. **Times per user** materializes as a **Cube pre-aggregation grouped by `user_id`**. Card form emits a `pre_aggregations:` block; inner agg becomes a column in the pre-agg, outer agg becomes a measure on the pre-agg.
3. **Register opens a Pull Request.** No more in-memory stub. Register screen emits a YAML diff against `cube/model/{cubes,views}/*.yml`, opens a PR via `gh`, runs through human approval, then a service (call it `catalogue-materializer`) picks up the merged PR and executes: Cube reload + pre-agg build + feature-store registration. Catalogue UI tails PR + service status with a state machine `draft → in_review → approved → materializing → live`.
4. **Home is views-first.** New `home.jsx` lists Cube views (`user_audience`, `revenue_metrics`, `activity_metrics`, `user_360.user_profile / user_activity_timeline / user_recharge_timeline / user_transactions`). New `view.jsx` is per-view detail. `events.jsx` is demoted to a drill-down inside a view's "Source events" tab.

Additional deltas surfaced by the cross-walk against `cube/model/*.yml`:

5. **Primitive card grid grows 6 → 8.** Adds **Segment** (emits `segments:` block) and **Bucket / Bin** (emits `dimension.case:` block — pattern proven by `txn_value_band_vnd` in `recharge.yml:101-114`).
6. **Freshness chip** on every event row, view tile, and measure preview, sourced from Cube `refresh_key`.
7. **Grain badge** on events: "Grain: transaction / user-day / user (lifetime)", inferred from the source cube's primary key.
8. **Reachable-via-joins** sub-section in the event drawer's Lineage tab, sourced from Cube `joins:` blocks. Without it PMs can't even know that `purchase_completed` can be sliced by `mf_users.spend_tier`.
9. **PII → `public: false`** propagation. Toggling the PII chip on a property sets `public: false` on the emitted dimension; measures depending on it inherit a "private" badge.
10. **Bidirectional lineage** in the drawer's Lineage tab: upstream (cubes joined + views containing this event) and downstream (artifacts consuming it).

---

## 1. Problem & Job-to-be-Done

A non-tech user (PM, growth analyst, marketer) sits in front of a raw events table on top of a Cube.dev semantic layer over Trino. They want to: **understand the data → validate a hypothesis → mint a new metric** that the data pipelines will materialize and serve through a feature store / metrics catalogue.

**Today (v1 demo)** the app has:
- `events.jsx` — event dictionary with inline desc-edit, properties table, "Use in: Funnel / Cohort / Flow / Metric" CTAs
- `formula.jsx` — A/B/C input + operators + templates-dropdown + preview + register handoff
- `register.jsx` — SQL preview, classification, submit
- `library.jsx`, `funnel.jsx`, `cohort.jsx`, `flow.jsx`, `retention.jsx`, `home.jsx`, `detail.jsx`

**Two gaps to close:**

1. **Q1 — Semantic enrichment is too shallow.** Inline desc-edit only. No owner / domain / tier / verified flag / property-level metadata (enum, PII, suggested measure).
2. **Q2 — The formula-bar floats above a hardcoded measure list.** A PM cannot mint a new measure from a raw event. The three-layer model is collapsed to one screen.

**The fix is three layers:**

```
Layer 0  Raw event           events.jsx (existing, enrich)
Layer 1  Aggregation primitive   measure.jsx (NEW)
Layer 2  Composition (formula)   formula.jsx (existing, refactor)
Layer 3  Templates (funnel/etc) tab inside formula.jsx (promote from dropdown)
```

---

## 2. Design Principles (non-negotiable)

1. **One decision per screen.** Each layer = one screen. No "everything at once" forms.
2. **Two fields max per primitive.** Sum = column + filter. Count = filter. Anything more kills "feels easy".
3. **Live value preview, always.** Every form has a single big number on the right and a 14-point sparkline. Pattern already exists in `formula.jsx` — reuse.
4. **Read-only Cube YAML preview.** Every authoring screen shows the YAML it will emit, collapsed by default. Earns trust from data engineers.
5. **Provenance dot + status badge on every artifact.** `green / amber / gray` already exists. Add `✓ verified / ⚠ incomplete / ⛔ deprecated` overlay.
6. **Compliance is informational, never blocking.** Show "fix me" hints. Never gate save.
7. **Inherit the existing design system.** `--orange-600`, `--blue-700`, `font-mono`, `Pill`, `Badge`, `Button`, `Icon`, `ProvDot`, `formula-bar`, `radius-md`, `shadow-lg`. Do not introduce a new palette or component library.
8. **Keyboard-first formula editing.** Cursor-aware insert for operators and A/B/C tokens already works — preserve it.

---

## 3. Information Architecture (view-first, post-patch)

```
Home                          ← home.jsx (NEW — view picker)
├── Explore
│   ├── Views                ← view.jsx (NEW — per-view detail; tabs: Measures / Events / Lineage)
│   │     └── (drill-down)
│   │         └── Source events  ← events.jsx (modified — drawer overlay, no longer top-nav)
│   └── (later) Tables
├── Build
│   ├── Measure              ← measure.jsx (NEW — Layer 1, 8 primitives incl. Segment + Bucket)
│   ├── Derived metric       ← formula.jsx (modified — was "Metric"; vocab split)
│   ├── Funnel               ← funnel.jsx (unchanged)
│   ├── Cohort               ← cohort.jsx (unchanged)
│   ├── Flow                 ← flow.jsx (unchanged)
│   └── Retention            ← retention.jsx (unchanged)
├── Library                  ← library.jsx (unchanged for now — splits Measure / Derived metric / Property in v2.1)
└── Register handoff         ← register.jsx (modified — PR-based; Mode required)
```

**Primary flow (happy path, view-first):**

```
home.jsx
  → pick a view (e.g. "revenue_metrics")
  → land on view.jsx
      tabs: [Measures] [Source events] [Lineage]
      freshness chip + grain badge in header
      "Define a measure on this view" CTA
                  │
                  ▼
       (alt path) Source events tab
         → click event row (e.g. purchase_completed)
         → drawer opens (Metadata / Properties / Lineage tabs)
         → action grid: [Funnel] [Cohort] [Flow] [Define a measure]
                                                  │
                                                  ▼
                                        measure.jsx (NEW)
                                        pick primitive (Sum/Count/Unique/Ratio/
                                          Derived Ratio/Times-per-user/
                                          Segment/Bucket)
                                        fill 1-2 fields, live preview
                                        Cube YAML preview (read-only)
                                        [Register measure] OR [Use in derived metric]
                                                  │
                                                  ▼
                                        formula.jsx (Layer 2 — DERIVED METRIC)
                                        tabs: [Templates] [Custom formula]
                                        new measure available in A/B/C dropdown
                                        Mode toggle (Derived metric / Property) — required
                                                  │
                                                  ▼
                                        register.jsx (PR-based)
                                        → opens PR via gh
                                        → status timeline: draft → in_review →
                                          approved → materializing → live
                                        → catalogue-materializer service picks up
                                          merged PR and executes
```

Note: vocabulary in nav. Old label "Metric" is replaced with "Derived metric" in Build nav and in the formula.jsx page title. "Measure" stays separate.

---

## 4. Screen specs

### 4.0 `home.jsx` — NEW (view-first entry)

**Purpose.** Replace the current home page with a Cube-view picker. PMs land here. Events are no longer the entry point.

**Layout.** A vertical stack of view cards, grouped by job-to-be-done.

**Groups + cards (sourced from `cube/model/views/user_360.yml`):**

- **One user at a time (360)**
  - `user_profile` — wide profile row
  - `user_activity_timeline` — day-by-day activity
  - `user_recharge_timeline` — day-by-day revenue
  - `user_transactions` — per-transaction recharge events
- **Cohorts & audiences**
  - `user_audience` — segmentation across mf_users
- **Time-series metrics**
  - `revenue_metrics` — daily/monthly revenue
  - `activity_metrics` — DAU/MAU/activity-day

**Each card shows:**

- View name (mono) + display title (sentence case)
- Description (one line, from YAML `description:`)
- Freshness chip — sourced from the underlying cube's `refresh_key` (e.g. "Refreshes every 5 min", "Daily, last updated 03:00")
- Grain badge — "Grain: user (lifetime)" / "user-day" / "transaction"
- # of measures + # of source events
- CTA: `[Open]` → `view.jsx?view=<name>`

**Empty state for new orgs:** "No views yet. Ask a data engineer to define a Cube view, or browse raw events."

---

### 4.0b `view.jsx` — NEW (per-view detail, drill-down host)

**Purpose.** Show what a view exposes and let PMs author measures against it.

**Header.**
```
Home / Explore / user_audience                                        
─────────────────────────────────────────────────────────────────────
Segmentation surface across mf_users.
Grain: user (lifetime)  ·  Refreshes every 1 hour  ·  7 measures · 1 source event
                                                  [Define a measure on this view]
```

**Tabs.**

- **Measures** (default) — list of measures currently exposed by the view. Each row: name, type (sum/count/...), unit, freshness, "Used in N derived metrics", "View YAML" link.
- **Source events** — list of cubes joined into this view (e.g. `mf_users`, `recharge`, `active_daily`). Click an event row → opens the events.jsx drawer overlay scoped to that event.
- **Lineage** — bidirectional: upstream cubes joined (and the join keys), downstream derived metrics built on this view's measures.

**Action.** The page-level `[Define a measure on this view]` CTA routes to `measure.jsx?view=<name>` with the view bound (event pre-bound is optional).

---

### 4.1 `events.jsx` — modify

**Today.** Two-pane split: event list (left) + event detail (right). Inline desc-edit pencil. Action grid `[Funnel][Cohort][Flow][Metric]`.

**Change.**

#### 4.1.1 Left pane — event row

Add two elements to each row, right of the existing `ev-meta` block:

- **Owner avatar** — 18 px circle, monogram (e.g. `KT` for Khoi Tran). Defaults to a gray "?" icon if unset. Tooltip: "Owner: Khoi Tran (Data team)" or "No owner — click to assign".
- **Compliance badge** — small pill, one of:
  - `✓ verified` — green outline. Means: description ≥ 20 chars + owner set + domain set + tier set.
  - `⚠ incomplete` — amber outline. Hover → list of missing fields with inline "Fix" link that opens the drawer focused on that field.
  - `⛔ deprecated` — gray with strikethrough event name.

Provenance dot stays — orthogonal axis (data source maturity).

#### 4.1.2 Right pane — promote inline edit to a tabbed drawer

Replace the inline pencil + scattered metadata with a **rich side drawer** triggered by a "Rich edit" button in the right pane header. Drawer width: 480 px, slides in from the right, overlays content, dimmable backdrop. Use existing `shadow-lg` and `radius-md`.

**Drawer tabs (top of drawer):**

- **Metadata** (default)
  - Display name (text input, distinct from `event.id` which stays the technical name)
  - Description (textarea, 280-char counter)
  - Owner (dropdown of team members; allow "Unassigned")
  - Domain (single-select chip group: Monetization / Engagement / Retention / Acquisition / Other)
  - Tier (radio: Core / Secondary / Exploratory — explain inline: "Core = production-grade, Secondary = in-use, Exploratory = WIP")
  - Verified toggle (auto-flips ✓ when the four required fields are filled, but PM can manually mark verified)
  - Tags (free-text chips)
- **Properties**
  - Table — replace today's 3-column with 4-column:
    - col 1: type icon + name
    - col 2: sample value
    - col 3: **metadata chips** — `[enum: {VND, USD, THB}]` (click to edit enum list), `[PII]` (amber chip), `[suggested measure: sum(amount_local)]` (clickable — routes to `measure.jsx?event=...&primitive=sum&column=amount_local`)
    - col 4: actions — pencil to edit property metadata, three-dot for "mark deprecated"
  - "Add property metadata" button below the table (lets a PM annotate even if upstream schema is bare)
- **Lineage**
  - List of artifacts that consume this event: metrics, cohorts, funnels, flows. Each is a clickable chip routing to the respective detail page. Pulled from a `used_in` array on the event record.
  - Empty state: "No artifacts use this event yet. Define a measure to start."

**Drawer footer:**

- Left: "Last edited 3 days ago by KT" — small mono text
- Right: `[Cancel]` `[Save]` — Save is disabled until something changed. Save flips the row's compliance badge if the four required fields are now satisfied.

#### 4.1.3 Right pane — action grid

Replace the current `[Funnel][Cohort][Flow][Metric]` quad with: `[Funnel][Cohort][Flow][Define a measure]` (primary, orange). "Define a measure" routes to `measure.jsx` with `?event=<id>` pre-bound. "Metric" entry is removed because the journey is now: event → measure → metric, not event → metric directly. (Power users can still get to `formula.jsx` from the Build nav.)

#### 4.1.4 States

- **Empty list** (search returns nothing): "No events match `<query>`. Try a shorter term or remove the active-only filter."
- **Empty lineage**: see above.
- **Drawer first-open for an undocumented event**: pre-focus the Description textarea, show a one-line tip: "Describe what triggers this event. Examples below." Three example descriptions in a faded panel beneath the textarea.

---

### 4.2 `measure.jsx` — NEW screen

**Purpose.** Layer 1 — mint an atomic measure from a raw event. The screen the demo is missing.

**Layout.** Two-pane split, similar to `events.jsx`:

- **Left pane (340 px):** vertical list of primitive cards.
- **Right pane:** dynamic form for the selected primitive + live value preview + read-only Cube YAML preview.

#### 4.2.1 Page head

```
Home / Build / New measure / [event_id chip]
─────────────────────────────────────────────
Define a measure on  purchase_completed
Pick how to aggregate. You'll be able to use this measure
in any metric, funnel, or cohort.
─────────────────────────────────────────────
[Cancel]                    [Save draft]  [Register measure]
```

The `[event_id chip]` is removable — clicking the × returns to the event picker (a slim modal listing events, search-first).

#### 4.2.2 Left pane — eight primitive cards

Cards are stacked vertically (not a grid — Statsig uses a 2-column grid; we use vertical to leave room for the form on the right). Each card has:

- An icon (Lucide: `sigma`, `hash`, `users`, `divide`, `divide-circle`, `repeat`, `filter`, `bar-chart-horizontal`)
- A title (Sum / Count / Unique Count / Ratio / Derived Ratio / Times per user / **Segment** / **Bucket**)
- One-line description (the exact copy below)
- An "Example" hint in muted mono font under the description
- A YAML target chip — small mono pill on the card's right edge showing the YAML block this primitive emits (e.g. `measure: sum`, `segments:`, `dimension: case:`, `pre_aggregations:`). Quietly teaches the Cube layer to PMs without leaving the card grid.

**Copy:**

| Card | Description | Example hint | YAML target |
|---|---|---|---|
| **Sum** | Total of a numeric column. | `sum(amount_local) → 558,920,000` | `measure: sum` |
| **Count** | Number of rows matching a condition. | `count(purchase_completed) → 18,213` | `measure: count` |
| **Unique Count** | Distinct values in a column. | `count_distinct(user_id) → 4,118` | `measure: count_distinct` |
| **Ratio** | One existing measure divided by another. | `revenue_local / purchase_count → 30,690 VND` | `measure: number` |
| **Derived Ratio** | Ratio computed from two columns in the same table. | `SUM(amount_usd) / SUM(amount_local) → 0.000041` | `measure: number` |
| **Times per user** | Per-user aggregation, then aggregated across users. | `avg of count(events) per user → 3.4` | `pre_aggregations:` + `measure: number` |
| **Segment** *(new)* | Reusable boolean filter expression. Use it as a one-click chip in any measure or derived metric. | `spend_tier = 'whale' AND country = 'VN'` → segment `vn_whales` | `segments:` |
| **Bucket** *(new)* | Bin a numeric column into named bands. | `charged_value` → `{<10K, 10K-50K, 50K-200K, 200K-1M, >=1M}` | `dimension: case:` |

Selected card: orange left border (4 px, `--orange-600`), light background tint, bold title. Inactive: hover lightens.

#### 4.2.3 Right pane — primitive form (varies by card)

Always shows three blocks: **Inputs** → **Preview** → **YAML** (collapsed).

**Inputs block — varies by primitive:**

- **Sum**
  - Column picker (dropdown of numeric columns on the bound event; type-ahead, shows sample value)
  - Optional filter builder (rows: `property` `operator (= ≠ > < ≥ ≤ in not in)` `value`; `[+ Add filter]`)
- **Count**
  - Optional filter builder (same as Sum)
- **Unique Count**
  - Column picker (dropdown of any column; defaults to `user_id` if present)
  - Optional filter builder
- **Ratio**
  - Numerator: dropdown of existing measures (from `window.MC_DATA.measures`)
  - Denominator: same dropdown
  - Inline preview: `<num_value> / <denom_value> = <result>`
- **Derived Ratio**
  - Numerator column (numeric)
  - Denominator column (numeric)
  - Optional filter builder
  - Auto-wraps with `NULLIF(SUM(denom), 0)` — show this in YAML preview
- **Times per user**
  - Inner aggregation: radio (Count of events / Sum of column / Unique count of column)
    - If "Sum of column" or "Unique count of column": column picker appears below
  - Outer aggregation across users: radio (Average / Median / P95 / Max / Min)
  - Optional filter builder applies to inner agg
  - YAML preview shows a **`pre_aggregations:` block grouped by `user_id`** plus a derived `measure:` of `type: number` that reads from the pre-agg. (Decision 2026-05-14 16:51 — see §0 patch.)
- **Segment** *(new)*
  - Reusable boolean. Inputs: filter builder rows (property + operator + value, AND-ed; group an OR with `[+ OR group]`).
  - Optional name (auto-derived from the expression: `vn_whales` from `country=VN AND spend_tier=whale`).
  - YAML preview shows a `segments:` block under the source cube.
  - Live preview shows the user/row count matching the segment.
- **Bucket** *(new)*
  - Inputs: numeric column picker + ordered breakpoints (number inputs, `[+ Add breakpoint]`).
  - Per-band labels (auto-derived, editable): for breakpoints `[10000, 50000, 200000, 1000000]` defaults to `< 10K / 10K-50K / 50K-200K / 200K-1M / >= 1M`.
  - YAML preview shows a `dimension.case:` block. (Pattern proven by `txn_value_band_vnd` in `recharge.yml:101-114`.)
  - Live preview shows row count per band as a horizontal bar list.

**Auto-generated name + ID:**

- Below the inputs block, an "Identification" mini-section:
  - Name (text input, auto-filled — e.g. `Sum of amount_local on purchase_completed` → user can edit to "Purchase Revenue (local)")
  - ID (mono, read-only, auto-derived from name: `purchase_revenue_local`)
  - Description (textarea, 280-char counter, pre-filled with "Total amount_local across purchase_completed events.")
  - Unit pill (Currency / Count / Ratio / Duration / Other — auto-detected from primitive type + column type, overridable)

**Preview block (right side, sticky if room):**

- Reuse `preview-card` styles from `formula.jsx`:
  - Big number (live-evaluated against mock data — for the prototype, deterministic fake values based on the event's volume)
  - Sub-label (unit)
  - 14-point sparkline below (existing pattern)
  - `ProvFooter` (grain / source / ms / dot)

**YAML block (collapsed accordion at the bottom):**

```yaml
# cube/model/cubes/<source>.yml — measure block
measures:
  - name: purchase_revenue_local
    description: "Total amount_local across purchase_completed events."
    type: sum
    sql: amount_local
    filters:
      - sql: "{CUBE}.event_name = 'purchase_completed'"
    meta:
      owner: khoitn
      domain: monetization
      tier: core
      unit: currency
```

Read-only, syntax-highlighted (reuse `colorize` helper from `register.jsx`). "Copy" button in the top-right of the YAML block.

#### 4.2.4 Footer CTAs

- `[Cancel]` — discard
- `[Save draft]` — saves to a local "drafts" list (shows in Library v2.1)
- Primary action group, two buttons:
  - `[Register measure]` (primary) — adds to the catalogue; routes to a slim success state (toast + "View in library / Build a metric using this")
  - `[Use in metric formula]` (default) — registers the measure AND routes to `formula.jsx` with this measure pre-loaded as input A

Disable both primary CTAs if name is empty or there is a filter-row validation error.

#### 4.2.5 States

- **No event bound** (entered from Build nav without `?event=...`): show a slim event picker modal first. Cannot pick a primitive until an event is bound.
- **Ratio with no measures yet** (catalogue is empty): show inline empty state inside the dropdown: "No measures yet. Define a Sum or Count first." With a quick-action chip "Switch to Derived Ratio" (which works directly off columns).
- **Times per user — Cube materialization commitment**: a small `Badge variant="info"` near the YAML block: "This measure builds a Cube pre-aggregation grouped by `user_id`. First build runs after PR merge (typically <10 min for ≤10M rows)." The badge links to a one-line explanation panel: "Why a pre-aggregation? Two-stage aggregation (per-user then across users) is too slow live; we materialize it nightly + on-demand."

---

### 4.3 `formula.jsx` — modify

**Today.** Single-column wizard (in `split` layout): inputs A/B/C → formula bar → meta. Templates hidden in a `Templates ▾` dropdown next to operators. Mode toggle (Metric / Property) buried at the bottom inside "Identification".

**Change.**

#### 4.3.1 Promote templates to top-level tabs

Above the inputs block, add a tab bar:

```
┌─────────────┬─────────────────────┐
│ Templates   │ Custom formula      │   ← tabs, "Custom formula" default-active for now
└─────────────┴─────────────────────┘
```

**Templates tab content:**

A 2×3 card grid (or 4-card row if narrow):

- **Daily Active Users** — `count_distinct(user_id) where event_name in (selected events)`
- **Conversion rate** — `count_distinct(users_did_B) / count_distinct(users_did_A)`
- **Retention curve** — D1 / D7 / D30 return-rate; user picks reference event ("registered on") and return event
- **Funnel** — multi-step event chain with conversion at each step
- **Cohort overlap** — % of cohort A who also belong to cohort B
- **Rate of change** — `(this_week - last_week) / last_week`

Each card: icon + title + one-line desc + "Fill template" CTA (chip). Clicking auto-fills inputs A/B/C and the formula, then switches to "Custom formula" tab so the PM can review and tweak.

**Custom formula tab content:** the existing `inputsBlock` + `formulaBlock` + `previewBlock` + `meta` (re-arranged below — see 4.3.3).

#### 4.3.2 Updated inputs block — measures from `measure.jsx` flow in

The A/B/C input cards stay (letter chip, "From a measure/cohort/metric", measure name, filter chips). Two updates:

- The measure picker dropdown is now populated from `window.MC_DATA.measures` **plus** any measure the user registered in `measure.jsx` during the session (stored in `window.MC_DATA.userMeasures` for the prototype).
- Inline "+ New measure" link at the bottom of the picker dropdown → routes to `measure.jsx` and returns with the new measure pre-bound when registered.

#### 4.3.3 Promote Mode toggle to a prominent decision before register

Vocabulary note: this screen authors **derived metrics** (Layer 2 — `type: number` over measure refs). Page title is "New derived metric"; primary CTA in section 4.3.x and below reads `[Register derived metric]`.

Move the "Derived metric / Property" radio out of the bottom-of-page Identification section into a **callout band** above the register footer:

```
┌────────────────────────────────────────────────────────────────────┐
│  Is this a derived metric or a property?                           │
│                                                                    │
│  ◉ Derived metric — one number per query, charted, registered as   │
│                     `measure: type: number` on a Cube view.        │
│                                                                    │
│  ○ Property — computed per-event or per-user; registered as a      │
│              `dimension:` and surfaced as a feature in the         │
│              feature store.                                        │
│                                                                    │
│  Pick one. This decides which YAML block we emit on register.      │
└────────────────────────────────────────────────────────────────────┘
```

Pre-register guard: if Mode is unset, `[Register derived metric]` shows a tooltip and is disabled.

#### 4.3.4 Templates dropdown — remove from formula keys

The existing `Templates ▾` button next to operators is removed (now lives in the top tab). The operator keys (`+ − × ÷ ( ) %`) and A/B/C chips stay.

#### 4.3.5 States

- **Empty entry (user lands without seeding from `measure.jsx`)**: top of Custom formula tab shows a slim banner: "Tip: define a measure first if your primitive is a sum / count / unique count. Otherwise pick a template." with two chips: `[Define a measure]` → `measure.jsx`, `[Browse templates]` → switches tab.
- **Formula validation error**: existing red badge on formula bar, unchanged.

---

### 4.4 `register.jsx` — modify (now PR-based, post-patch §0.3)

**Today (pre-patch).** SQL preview, domain dropdown, games multi-select, latency, use-case textarea, submit-to-stub.

**Post-patch.** Submit produces a real YAML diff against `cube/model/{cubes,views}/*.yml`, opens a Pull Request via `gh pr create`, and the catalogue UI tails PR + service status. No in-memory measure store.

#### 4.4.1 Read Mode + vocabulary from formula.jsx / measure.jsx state

Show entry type as a read-only badge at the top of the page:

```
[Measure]          Purchase Revenue (local)   purchase_revenue_local
[Derived metric]   Whale 7-day Recharge Rate  whale_recharge_rate_7d
[Property]         Lifecycle Stage            lifecycle_stage
```

Three possible badges now (was two): **Measure** (from measure.jsx), **Derived metric** (from formula.jsx with Mode=derived metric), **Property** (from formula.jsx with Mode=property). If somehow the page is reached without one, redirect back to the originating screen with a toast.

#### 4.4.2 "What this becomes" panel — YAML target stated upfront

Mono-styled card above the SQL/YAML block. Copy is now exact about the YAML target:

- **Measure (atomic — Sum/Count/Unique/Ratio/Derived Ratio):**
  > On register, this becomes a `measure:` block under the source cube. PR target: `cube/model/cubes/<source>.yml`. The `catalogue-materializer` service reloads Cube on merge.
- **Measure (Times per user):**
  > On register, this becomes a `pre_aggregations:` block grouped by `user_id` plus a `measure: type: number` reading from it. PR target: `cube/model/cubes/<source>.yml`. First build runs on merge.
- **Measure (Segment):**
  > On register, this becomes a `segments:` block under the source cube. PR target: `cube/model/cubes/<source>.yml`.
- **Measure (Bucket):**
  > On register, this becomes a `dimension:` block with a `case:` expression. PR target: `cube/model/cubes/<source>.yml`.
- **Derived metric:**
  > On register, this becomes a `measure: type: number` on view `cube/model/views/<view>.yml`, referencing the input measures. The `catalogue-materializer` service registers it in the feature store on merge.
- **Property:**
  > On register, this becomes a `dimension:` block (per-event on the source cube, or per-user on `mf_users`), and a feature in the feature store. PR target: depends on grain.

#### 4.4.3 Similar-entries block — dynamic

Replace the hardcoded "3 similar" panel with a real similarity computation against the same-type pool (measures look at measures; derived metrics look at derived metrics; properties at properties). Prototype: substring match on formula / column / filter expression. Each match: name, ID, one-line desc, "View" link.

#### 4.4.4 Register form — PII inheritance check

If any input column / measure ref has `public: false` (PII inherited), surface a callout above the YAML block:

> **Private inputs detected.** Measure `appsflyer_id_count` depends on PII property `appsflyer_id`. The registered entry will inherit `public: false` and will not appear in the public Catalogue API. Maintainers can still query it via the engineer-grade Cube SQL endpoint.

Cannot be dismissed; cannot block submit.

#### 4.4.5 Submit — open a PR

Replace the current submit-to-stub with a three-step modal flow:

**Step 1 — Preview the diff.**

Full-screen modal. Two-column diff view:

- Left: current `cube/model/<path>.yml`
- Right: proposed (with the new block highlighted)

Shows: file path, line range, block being inserted/modified. PM can `[Cancel]` (return to form) or `[Looks good →]`.

**Step 2 — PR metadata.**

- Title (auto-filled — `feat(catalogue): add measure purchase_revenue_local`; PM can edit)
- Body (auto-filled — uses the description + use-case textarea + a "What this becomes" recap; PM can edit)
- Reviewer (dropdown of data-team members; required)
- Branch name (read-only, auto-derived — `catalogue/measure/purchase_revenue_local`)
- Labels (auto: `catalogue`, `measure`/`derived-metric`/`property`, the source cube)

CTA: `[Cancel]`  `[Open PR]`. Clicking `[Open PR]` calls the backend, which runs `gh pr create` on a service account against `cube/model/`.

**Step 3 — Status & wait.**

After PR opens, the form is replaced by a status timeline:

```
draft  →  in_review  →  approved  →  materializing  →  live
  ●         ○             ○              ○              ○
```

Each node:
- **draft** — PR just opened
- **in_review** — reviewer assigned, CI running (validates YAML against Cube schema, lint, dry-run query)
- **approved** — reviewer marked LGTM (PR not yet merged — final guard for the PM)
- **materializing** — PR merged; `catalogue-materializer` service is reloading Cube and (if applicable) running the first pre-agg build
- **live** — service confirmed health-check; entry available in Library

Each node has a timestamp. The PR URL is shown as a chip at the top of the timeline. A "View PR on GitHub" link opens the PR in a new tab.

**Final actions** in the live state:

- `[View in library]` → library.jsx with the new entry highlighted
- `[Build on this]` → routes back to formula.jsx (if Measure) or measure.jsx with the new entry available
- `[Done]` → home

If status stalls at any node for > 24h, the timeline shows a `⚠ Stalled` badge and a "Ping reviewer" / "Re-run service" action.

#### 4.4.6 States

- **Service unhealthy** at materialize step: red banner, "The catalogue-materializer service is unhealthy. The PR is merged; the registration will retry automatically every 5 min. Last error: ..." with a link to the service logs (internal team only).
- **CI failed**: timeline shows `in_review` node with `⛔ CI failed`. Inline diff of the CI output, link to the workflow run.
- **PR rejected**: timeline replaced by "PR closed without merge" + reviewer's comment. CTA `[Edit and resubmit]` returns to the form pre-filled.

---

## 5. Component specs (new + modified)

### 5.1 `<PrimitiveCard />` — NEW

Props: `icon`, `title`, `description`, `exampleHint`, `selected`, `onClick`

Visual:
- 12 px border-radius, 1 px border (var(--border)), padding 14 px
- Selected: 4 px orange left bar, `background: var(--muted)`, title `font-weight: 600`
- Hover (unselected): `background: var(--muted-foreground/0.04)`
- Icon: 20 px, top-left
- Title: 14 px
- Description: 12.5 px, muted
- Example hint: 11 px mono, muted, single-line truncate

### 5.2 `<MetadataDrawer />` — NEW

Props: `event`, `open`, `onClose`, `onSave`

Layout:
- Fixed right, 480 px wide, full-height
- Header: event id (mono) + close button
- Tab bar (3 tabs)
- Scrollable content per tab
- Footer (sticky): last-edited line + Cancel/Save

Use existing `Pill`, `Badge`, `Button`, `Input`, textarea styles.

### 5.3 `<PropertyChip />` — NEW

Props: `kind` (`enum` | `pii` | `suggested-measure` | `deprecated`), `value`, `onClick?`

Visuals:
- `enum`: outline, mono label, clickable
- `pii`: amber filled background, lock icon
- `suggested-measure`: blue outline, sigma icon, clickable (routes to measure.jsx)
- `deprecated`: gray, strikethrough

### 5.4 `<ComplianceBadge />` — NEW

Props: `status` (`verified` | `incomplete` | `deprecated`), `missingFields?: string[]`, `onFix?`

Visuals: tiny pill, 18 px height. Hover shows tooltip with missing field list and a "Fix" link.

### 5.5 `<FilterBuilder />` — NEW

Props: `properties`, `value`, `onChange`

Rows of `<property select> <operator select> <value input>` with `[+ Add filter]` and a `[× remove]` per row. Operators: `= ≠ > < ≥ ≤ in not in is null is not null`.

### 5.6 `<YamlPreview />` — NEW

Props: `yaml: string`, `collapsed?: boolean`

Reuse `colorize` from register.jsx but for YAML syntax. Copy button top-right. Collapsed by default in measure.jsx, expanded in register.jsx.

### 5.7 `<TemplateCard />` — NEW (formula.jsx template tab)

Props: `icon`, `title`, `description`, `onPick`

Visuals similar to `PrimitiveCard` but in grid layout. Each card has a "Fill template" chip CTA in the bottom-right.

### 5.8 `<ModeCallout />` — NEW

Props: `value: 'derived-metric' | 'property'`, `onChange` (post-vocab-split; was `'metric' | 'property'`)

The prominent band described in 4.3.3. Uses existing radio-group styling (`register-radio` class exists already).

### 5.9 `<FreshnessChip />` — NEW (post-patch)

Props: `refreshEvery: '5 minute' | '1 hour' | 'daily' | 'realtime'`, `lastUpdatedAt?: number`

Visuals: small chip, clock icon, mono label. Examples: `↻ 5m · 12s ago`, `↻ 1h · 47m ago`, `↻ daily · 03:00`.
Source: Cube `refresh_key.every` on the bound cube.
Used on: home view tiles, view.jsx header, measure preview cards.

### 5.10 `<GrainBadge />` — NEW (post-patch)

Props: `grain: 'transaction' | 'user-day' | 'user-lifetime' | 'session' | 'custom'`, `customLabel?: string`

Visuals: tiny badge, mono. Color-coded: transaction (blue), user-day (purple), user-lifetime (orange).
Source: inferred from the source cube's `primary_key` dimension + join cardinality (best-effort heuristic for prototype; data team confirms on PR).
Used on: home view tiles, view.jsx header, event rows in events.jsx.

### 5.11 `<PrDiffPreview />` — NEW (register step 1)

Props: `currentYaml: string`, `proposedYaml: string`, `filePath: string`

Visuals: full-screen modal. Two-column diff (left current, right proposed) with new lines highlighted green. Header shows file path. Footer: `[Cancel]` `[Looks good →]`.
Reuse `colorize` helper.

### 5.12 `<PrSubmitForm />` — NEW (register step 2)

Props: `defaultTitle`, `defaultBody`, `defaultBranch`, `defaultLabels`, `reviewers: User[]`, `onSubmit`

Visuals: form fields per §4.4.5 step 2. `[Open PR]` is disabled until reviewer is set.

### 5.13 `<PrStatusTimeline />` — NEW (register step 3)

Props: `prUrl: string`, `state: 'draft' | 'in_review' | 'approved' | 'materializing' | 'live' | 'stalled' | 'rejected' | 'ci_failed'`, `nodeTimestamps: Record<NodeName, number>`, `lastError?: string`

Visuals: horizontal 5-node timeline (per §4.4.5 step 3). Each node: dot + label + timestamp below. Connecting line darkens as state progresses. Inline error panels for `stalled`, `rejected`, `ci_failed`.

### 5.14 `<ReachableProperties />` — NEW (events.jsx drawer Lineage tab)

Props: `event: Event`, `joins: Join[]`

Lists properties reachable via the source cube's `joins:` block. Each row: `<source-cube>.<property>` mono label + a "use as filter" chip + a "use in measure" chip.

### 5.15 `<PiiInheritBadge />` — NEW

Props: `reason: string` (e.g. "Depends on PII property `appsflyer_id`")

Visuals: small amber pill with lock icon. Tooltip shows the dependency chain. Appears on Library entries and on register form for measures inheriting `public: false`.

---

## 6. Interaction patterns

1. **Drawer-from-row.** Clicking a row in events.jsx opens the right detail pane (existing). Clicking "Rich edit" in the right pane header opens the drawer overlay (new). Esc closes the drawer.
2. **Card grid selection.** In measure.jsx, clicking a primitive card swaps the right form. State is preserved per primitive while the user is on the page (e.g., switching from Sum to Count keeps the filter rows).
3. **Tab switching with state preservation.** In formula.jsx, clicking a template fills inputs A/B/C and the formula, then auto-switches to "Custom formula" tab so the PM sees the result. Tab state is preserved if the user clicks back.
4. **Live preview latency.** All preview blocks show a value within 100 ms (it's mock data). For realism, add a 220 ms fade-in.
5. **YAML copy.** Copy → toast "Copied" near the YAML block for 1.5 s.
6. **Inline route-and-return.** Clicking a `suggested-measure` chip in the events.jsx Properties tab opens measure.jsx with the primitive and column pre-bound. "Cancel" returns to events.jsx with the drawer reopened at Properties.
7. **Compliance recompute.** When the user edits Metadata in the drawer and saves, recompute the compliance badge on the row immediately. If now verified, show a brief confetti / checkmark microanimation (subtle).

---

## 7. Copy & microcopy

Tone: direct, terse, no marketing voice. Sentences end in periods. Imperative for CTAs.

| Surface | Copy |
|---|---|
| Drawer empty desc | "Describe what triggers this event. Examples below." |
| Compliance tooltip — incomplete | "Missing: description, owner, domain. Click to fix." |
| Compliance tooltip — verified | "Verified by Khoi · 2 days ago." |
| measure.jsx page subhead | "Pick how to aggregate. You'll be able to use this measure in any metric, funnel, or cohort." |
| Times-per-user warning | "This measure needs a pre-aggregation grouped by user_id. The data team materializes it on register." |
| Mode callout instruction | "Pick one. This affects how the data pipelines materialize it." |
| Register Mode read-only badge | `[Metric]` or `[Property]` — bold uppercase, 10 px |
| Empty events list | "No events match `<query>`. Try a shorter term or remove the active-only filter." |
| Templates tab empty banner (n/a — always shows 6 cards) | — |
| Register similar-metrics empty | "No similar metrics found. This one is novel." |
| Save measure success toast | "Measure registered. View in library or build a metric using this." |

---

## 8. Visual reference (ASCII)

### 8.1 events.jsx with new row layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ● purchase_completed                          KT  ✓ verified              ▸ │
│   ─ 18k/day · 14 reports                                                   │
└─────────────────────────────────────────────────────────────────────────────┘
  prov   id                                  owner  compliance         expand
```

### 8.2 Drawer overlay

```
                                                ┌──────────────────────────────┐
                                                │ purchase_completed         × │
                                                ├──────────────────────────────┤
                                                │ [Metadata][Properties][Lin.] │
                                                ├──────────────────────────────┤
                                                │ Display name                 │
                                                │ [ User Purchase            ] │
                                                │                              │
                                                │ Description (45/280)         │
                                                │ ┌──────────────────────────┐ │
                                                │ │ Fires when a user…       │ │
                                                │ └──────────────────────────┘ │
                                                │                              │
                                                │ Owner    [Khoi Tran      ▾] │
                                                │ Domain   [Monetization   ▾] │
                                                │ Tier     ◉ Core  ○ Sec…     │
                                                │ ✓ Verified                   │
                                                ├──────────────────────────────┤
                                                │ Last edited 3d ago  [Save] │
                                                └──────────────────────────────┘
```

### 8.3 measure.jsx layout

```
Home / Build / New measure / [purchase_completed ×]
─────────────────────────────────────────────────────────────────────────────
Define a measure on  purchase_completed
─────────────────────────────────────────────────────────────────────────────
                                       [Cancel]  [Save draft]  [Register]
─────────────────────────────────────────────────────────────────────────────

┌─ PRIMITIVES ───────────┐   ┌─ INPUTS ──────────────────────────────────┐
│ ● Sum                  │   │ Column                                    │
│   Total of numeric col │   │ [ amount_local                          ▾]│
│   sum(amt) → 558M      │   │ sample: 50,000                            │
├────────────────────────┤   │                                           │
│ ○ Count                │   │ Filter (optional)               [+ Add]   │
│   Rows matching cond.  │   │   currency  [= ▾]  [VND]           [×]   │
├────────────────────────┤   ├───────────────────────────────────────────┤
│ ○ Unique Count         │   │ Name                                      │
│   Distinct values      │   │ [ Purchase Revenue (local)               ]│
├────────────────────────┤   │ ID  purchase_revenue_local                │
│ ○ Ratio                │   │                                           │
├────────────────────────┤   │ Description (45/280)                      │
│ ○ Derived Ratio        │   │ [ Total amount_local across purchase…   ] │
├────────────────────────┤   │                                           │
│ ○ Times per user       │   │ Unit  [Currency ▾]                        │
└────────────────────────┘   └───────────────────────────────────────────┘

┌─ PREVIEW ─────────────────────────────────────────────────────────────────┐
│      558,920,000                                                           │
│      VND                                                                   │
│      ╱╲    ╱╲                                                              │
│   ╱╲╱  ╲╱╲╱  ╲╱╲    last 14 days                                          │
│                                                                            │
│   ● cube: purchase_completed · 312ms                                       │
└────────────────────────────────────────────────────────────────────────────┘

▾ Cube YAML preview
```

### 8.4 formula.jsx top of page

```
Home / Build / New metric
─────────────────────────────────────────────────────────────────────────────
Whale 7-day Recharge Rate                whale_recharge_rate_7d
─────────────────────────────────────────────────────────────────────────────
[Discard]                            [Save draft]    [Register metric]

┌────────────┬──────────────────┐
│ Templates  │ Custom formula ● │
└────────────┴──────────────────┘
```

---

## 9. Data shape changes (`data.js`) — post-patch

### 9.1 Views (NEW — top-level surface for view-first home)

```js
views: [
  {
    name: "user_audience",
    title: "User Audience",
    description: "Segmentation surface across mf_users.",
    sourceCubes: ["mf_users"],
    grain: "user-lifetime",          // 'transaction' | 'user-day' | 'user-lifetime' | 'session'
    refreshEvery: "1 hour",          // Cube refresh_key.every
    lastRefreshedAt: 1715683200000,
    group: "cohorts",                // 'one-user' | 'cohorts' | 'time-series'
    measureCount: 7,
    sourceEventCount: 1,
    jobToBeDone: "Segment users across cohorts; whales, at-risk, lapsed.",
  },
  // ... revenue_metrics, activity_metrics, user_profile, user_activity_timeline,
  //     user_recharge_timeline, user_transactions
]
```

### 9.2 Events — append metadata + grain + freshness

```js
{
  // existing fields
  owner: "khoitn",                // string id (or null)
  domain: "Monetization",         // enum
  tier: "core",                   // 'core' | 'secondary' | 'exploratory'
  verified: true,                 // boolean — auto-derived if needed
  tags: ["iap", "vng"],          // free chips
  displayName: "User Purchase",   // optional, defaults to id

  sourceCube: "recharge",         // NEW — links back to Cube YAML
  grain: "transaction",            // NEW — inferred from cube primary_key
  refreshEvery: "5 minute",        // NEW — from cube refresh_key

  properties: [
    {
      name: "amount_local",
      type: "#",
      sample: "50000",
      enum: null,                 // null OR ["VND","USD","THB"]
      pii: false,                 // toggling true → emits public: false in YAML
      suggestedMeasure: { primitive: "sum", column: "amount_local" }, // optional
      deprecated: false
    }
  ],

  reachableProperties: [           // NEW — sourced from Cube joins:
    { via: "mf_users", property: "spend_tier", joinKey: "user_id" },
    { via: "mf_users", property: "country", joinKey: "user_id" },
    // ...
  ],

  usedIn: [...],                  // downstream lineage (existing)
  usedBy: [...],                  // NEW — upstream lineage (views containing this event)
}
```

### 9.3 Registrations — PR state machine (replaces in-memory `userMeasures`)

The catalogue no longer stores measures locally. Each register attempt is a **registration** with PR + service state. The Library reads from a `MC_DATA.registrations` array that mirrors the backend.

```js
registrations: [
  {
    id: "purchase_revenue_local",
    kind: "measure",                // 'measure' | 'derived-metric' | 'property' | 'segment' | 'bucket'
    name: "Purchase Revenue (local)",
    desc: "Total amount_local across purchase_completed events.",

    // Layer-1 measure-specific
    primitive: "sum",
    column: "amount_local",
    event: "purchase_completed",
    sourceCube: "recharge",
    filters: [{ property: "currency", op: "=", value: "VND" }],
    unit: "currency",

    // Derived-metric specific (kind === 'derived-metric')
    formula: null,                 // e.g. "A / B"
    inputs: null,                  // [{ letter: "A", measureId: "..." }, ...]
    mode: null,                    // 'derived-metric' | 'property'
    targetView: null,              // e.g. "revenue_metrics"

    // PR + service state (NEW)
    pr: {
      url: "https://github.com/.../pull/427",
      number: 427,
      branch: "catalogue/measure/purchase_revenue_local",
      reviewer: "data-eng-lead",
      filePath: "cube/model/cubes/recharge.yml",
    },
    state: "live",                 // draft|in_review|approved|materializing|live|stalled|rejected|ci_failed
    stateHistory: [
      { state: "draft", at: 1715683200000 },
      { state: "in_review", at: 1715683260000 },
      { state: "approved", at: 1715684100000 },
      { state: "materializing", at: 1715684120000 },
      { state: "live", at: 1715684480000 },
    ],
    yaml: "...",                   // the generated YAML block (read-only)
    public: true,                  // false if any input is PII-tagged
    createdAt: 1715683200000,
  }
]
```

In-memory only for the prototype demo. The real backend (out of scope for v2.0 design) owns the source of truth; the catalogue UI tails the registration document over a webhook or polling.

### 9.4 Templates (unchanged — 6 template definitions in `MC_DATA.templates`)

### 9.5 Users (NEW — owner picker source)

```js
users: [
  { id: "khoitn", name: "Khoi Tran", team: "data", avatarInitials: "KT" },
  // ...
]
```

---

## 10. Out of scope (v2.0)

- Live data; the prototype runs on `MC_DATA`.
- Real Cube SQL execution; previews are deterministic fake numbers derived from `event.volume`.
- AI / NL-to-metric input field.
- Drag-and-drop measure composition (visual pipeline).
- Multi-user collaboration / comments.
- Revision history in the Metadata drawer (placeholder line is fine).
- Library v2 split (Measure / Derived metric / Property / Segment / Bucket tabs) — keep current library.jsx untouched in v2.0; do the split in v2.1.
- **PR flow backend** — design-only for v2.0. The catalogue UI shows the modal flow + status timeline against mocked PR + service responses driven by `MC_DATA.registrations`. Actual `gh pr create` integration + `catalogue-materializer` service ship in a separate engineering track.
- Mobile / responsive below 1024 px width — desktop-only prototype.
- Real Cube YAML emission — for v2.0 the YAML preview is hand-templated against a generator function; round-trip back from YAML to UI state is out of scope.

---

## 11. Acceptance criteria (post-patch — view-first, vocab-split, PR-based)

A PM can, in one session, with zero help from a data engineer:

1. Land on `home.jsx`. See a list of Cube **views** grouped by job-to-be-done. Pick `revenue_metrics`.
2. Land on `view.jsx?view=revenue_metrics`. See the view's freshness chip ("refreshes every 5 min"), grain badge ("transaction"), measures tab populated, source events tab listing `recharge`.
3. Click the Source events tab → click `purchase_completed`. The events.jsx drawer overlay opens. Fill description / owner / domain / tier, save, see the row's compliance badge flip to `✓ verified`.
4. Click `[Define a measure]` from the event detail action grid (or from the view header).
5. Land on `measure.jsx` with `purchase_completed` and `recharge` source cube pre-bound.
6. Pick **Sum**, choose `amount_local`, add filter `currency = VND`, see the live preview render, see auto-generated name `Purchase Revenue (local)`, see the Cube YAML preview emit a `measure:` block targeting `cube/model/cubes/recharge.yml`.
7. Click `[Use in derived metric]` → register flow runs (see step 11) and on `live`, route to `formula.jsx` with the new measure already in input A.
8. Switch to the **Templates** tab, pick **Conversion rate**, auto-fill the formula. Switch back to Custom formula, tweak.
9. Pick Mode = **Derived metric** in the prominent callout (vocab split — not "Metric").
10. Click `[Register derived metric]`.
11. **Register PR flow runs:** preview diff → open PR (assigns reviewer) → status timeline shows `draft → in_review`. CI passes. Reviewer approves and merges. Timeline shows `materializing → live`. PR URL is visible throughout.
12. Land on Library with the new derived metric highlighted. Both the measure (step 6) and derived metric (step 10) are visible with the correct badges (`[Measure]` / `[Derived metric]`).

Optional flows that must also work:

13. From `view.jsx?view=user_audience`, define a **Segment** primitive (`spend_tier = whale AND country = VN`). The register PR targets `cube/model/cubes/mf_users.yml` with a `segments:` block.
14. From `view.jsx?view=user_recharge_timeline`, define a **Bucket** primitive on `revenue_vnd` with breakpoints `[10000, 50000, 200000, 1000000]`. The register PR targets the source cube with a `dimension.case:` block.
15. From `view.jsx?view=user_audience`, define a **Times per user** measure (inner: count of `purchase_completed`; outer: avg). Register PR includes a `pre_aggregations:` block grouped by `user_id`. The timeline shows the materialization step taking longer (≤ 10 min). The badge in the form sets PM expectation correctly.
16. Define a measure on a PII-tagged property → the register form shows the "Private inputs detected" callout; the registered entry has a "private" badge in Library.

**Failure modes:**

If any of the above requires a hidden menu, a dropdown deeper than two levels, jumping to a different nav section to find a primitive, or seeing the wrong vocabulary ("metric" where it should be "measure" or "derived metric"), the design has missed.

---

## 12. Visual references / patterns to study (for the designer)

- [Statsig metric type picker](https://docs.statsig.com/metrics/metric-types/) — the card grid we are stealing for `measure.jsx`
- [Mixpanel Lexicon screenshots](https://docs.mixpanel.com/docs/data-governance/lexicon) — the drawer pattern for `events.jsx`
- [Amplitude Data Govern](https://amplitude.com/docs/data) — tier / owner / verified pattern
- [Looker calculations field UI](https://cloud.google.com/looker/docs/custom-fields) — formula-bar reference (we already match this)
- Reference codebase: `plans/reports/reference/Metrics-Catalogue/screens/` — all existing JSX

---

## 13. Open questions (post-patch)

**Resolved 2026-05-14 16:51 (see §0):**

- ~~Q1 Vocabulary~~ → **Separate.** "Measure" (Layer 1) and "Derived metric" (Layer 2) are distinct labels everywhere.
- ~~Q2 Times-per-user materialization~~ → **Cube pre-aggregations grouped by `user_id`.**
- (implied) ~~Register output~~ → **Pull Request → human approval → `catalogue-materializer` service.**
- (implied) ~~Home page entry~~ → **Views-first.**

**Still open:**

1. **Owner picker source.** Hardcoded team list for the prototype? Or pull from a `MC_DATA.users` mock? Likely `MC_DATA.users` so we can render avatars consistently.
2. **Filter values UX.** Free text vs property-aware (e.g., `currency` should suggest `VND / USD / THB` from the enum). **Tentative default: enum-aware if `property.enum` is set, free text otherwise.**
3. **Where do registered entries live in the Library?** One surface with `[Measure]` / `[Derived metric]` / `[Property]` / `[Segment]` / `[Bucket]` badges, or tabs? Decision affects library.jsx for v2.1.
4. **Compliance "verified" trigger.** Auto-flip when 4 required fields filled (description / owner / domain / tier), or require an explicit "Mark verified" toggle? Auto with manual override is the leading option.
5. **PR target cube vs view.** Atomic measures (Sum/Count/etc.) live on the source cube. Derived metrics (`type: number`) — do they live on the cube or on the view? Cube convention says **on the view** (so the user-facing view exposes derived metrics, not the underlying cube). Confirm with the data-engineering team before the PR template is finalized.
6. **Materialization-service identity.** "`catalogue-materializer`" is a placeholder. Does the service already exist (under a different name)? Or do we build a thin one that watches `cube/model/` for merged PRs? Either way, the catalogue UI only needs a status webhook contract.
7. **Branch protection on `cube/model/`.** PRs go to which base branch? `main`? A `cube/staging` branch with a separate Cube instance? Affects how aggressive the auto-merge / preview is.
8. **Service-account permissions for `gh pr create`.** Bot identity in commit metadata, reviewer assignment, label permissions. Standard infra setup but flag it.
9. **Reviewer routing.** Hardcoded per source cube, per domain (Monetization → Revenue team), or PM chooses? Recommend per-domain routing with PM override.
10. **Segment scope.** A segment defined on `mf_users` is reusable on any cube that joins `mf_users`. The UI should expose this — does the segment picker on measure.jsx scope to "segments available given the source cube + its joins"? Yes; flag for the reachability sub-resolver.

---

**Status:** READY-TO-PASTE.
Companion report: `researcher-260514-1547-event-semantics-and-metric-builder-ux.md` (Layer-1 addendum).
