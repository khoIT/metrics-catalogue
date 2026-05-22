# Research: Event Semantics & No-Code Metric Authoring — SOTA review for the Metrics Catalogue prototype

**Date:** 2026-05-14 (patched 2026-05-14 15:59 — Layer-1 addendum)
**Status:** DONE
**Report ID:** researcher-260514-1547-event-semantics-and-metric-builder-ux

---

## Errata / Layer-1 Addendum (2026-05-14 15:59)

The original report framed metric authoring as **2 layers** (event semantics → formula-bar composition). User flagged that this misses **Layer 1 — Aggregation Primitives** (Sum, Count, Unique Count, Ratio, Derived Ratio, Times-per-user), which is how a non-tech user actually mints a *measure* from a raw event before any composition. Statsig promotes these to a first-step card grid; that pattern is now incorporated.

**Three layers, not two:**

```
Layer 0 — Raw event (events.jsx)
   ↓ semantic enrichment (Q1: Mixpanel Lexicon pattern)
Layer 1 — Aggregation primitive  ← NEW
   Sum / Count / Unique Count / Ratio / Derived Ratio / Times-per-user
   Output: a registerable atomic measure (maps 1:1 to a Cube YAML `measure`)
   ↓
Layer 2 — Composition (formula.jsx A/B/C + operators)
   Output: a derived metric
   ↓
Layer 3 — Template (Funnel / Retention / Conversion)
   Pre-packaged Layer 1+2 combinations
```

Without Layer 1, the formula-bar floats above a fixed set of pre-baked measures (`dau`, `revenue_local`, `whale_users`) — a PM cannot self-serve a *new* measure from a raw event. This addendum:

- Adds **Pattern 0** (Aggregation Primitives — Statsig) to the Q2 Pattern Comparison.
- Inserts **Phase 2.5 (Primitive picker)** into the Recommended Hybrid Flow.
- Adds **two new rows** (5a, 5b) to the UI Deltas Table — one new `measure.jsx` screen + an entry-card grid on `formula.jsx`.
- Adds the Cube YAML / dbt MetricFlow mapping for each primitive.
- Adds an unresolved question on per-user aggregation (two-stage agg).

Everything in the original report below remains valid; the addendum is additive.

---

## Resolved Decisions (2026-05-14 16:51 — post-Cube-cross-walk)

After comparing the report's surface area against the live Cube YAML model in `cube/model/{cubes,views}/*.yml`, four open questions are resolved. Anywhere the body below contradicts these, the table wins.

| # | Question | Resolution | Implication |
|---|---|---|---|
| Vocab (was Q9 in §Unresolved) | "measure" vs "derived metric" | **Separate for clarity.** Layer 1 = **measure** (Cube atom — `type: count / sum / count_distinct / ...`). Layer 2 = **derived metric** (`type: number` over measure refs). UI labels enforce the split. | Button copy, library taxonomy, register-screen badge, and YAML preview all distinguish the two. Catalogue umbrella term is "catalogue entry"; never "metric" alone. |
| Times-per-user materialization (was Q8) | Sub-query measure or pre-aggregation? | **Cube pre-aggregations grouped by `user_id`.** Card form code-gens a `pre_aggregations:` block. Inner agg lands as a column in the pre-agg; outer agg becomes a measure that reads from the pre-agg. | YAML preview shows the pre-agg block; register copy makes the materialization commitment explicit: "this measure builds a pre-aggregation grouped by user_id; first build runs after PR merge." |
| Register output | Stub `data.js`, real backend, or git? | **Opens a Pull Request.** Register screen emits a YAML diff against `cube/model/{cubes,views}/*.yml`, opens a PR via `gh`, runs through human approval, then a service picks up the merged PR and executes (Cube reload + pre-agg materialization + feature-store registration). | Register screen state machine: `draft → in_review → approved → materializing → live`. Catalogue UI tails PR + service status. No catalogue-local measure store. |
| Home page entry | Events-first or views-first? | **Views-first.** Home lands on Cube **views** (`user_audience`, `revenue_metrics`, `activity_metrics`, `user_360.user_profile / user_activity_timeline / user_recharge_timeline / user_transactions`). Events become drill-downs inside a view's "Source events" tab. | events.jsx demoted from primary nav. New `home.jsx` is a view picker; new `view.jsx` is a per-view detail page with tabs (Measures / Events / Lineage). |

### Two new primitive cards (from the Cube cross-walk)

The card grid grows from **6 → 8**. Both new cards emit YAML blocks that Cube already supports first-class:

| New card | Inputs | Cube YAML emitted | Why it's needed |
|---|---|---|---|
| **Segment** | property + operator + value (filter row builder); optional name | `segments:\n  - name: <id>\n    sql: "<expr>"` on the source cube | PMs re-type the same `WHERE spend_tier = 'whale'` everywhere. Cube has reusable segments; expose them. Pattern proven by `iap / web / last_7d / whales / at_risk_paying` in `mf_users.yml` and `recharge.yml`. |
| **Bucket / Bin** | numeric column + ordered list of breakpoints + per-band labels | `dimensions:\n  - name: <id>\n    type: string\n    case:\n      when: [...]\n      else: ...` | PMs constantly want spend / level / age bands. Pattern proven by `txn_value_band_vnd` in `recharge.yml:101-114`. |

Full grid: **Sum / Count / Unique Count / Ratio / Derived Ratio / Times per user / Segment / Bucket**.

### Other Cube cross-walk gaps now flagged for the PRD (companion file)

- **View-first nav.** Home is a view picker; `events.jsx` is a drill-down inside a view.
- **Freshness chip** on every measure / event / view, sourced from Cube `refresh_key`.
- **Grain badge** on events ("Grain: transaction" / "Grain: user-day" / "Grain: user (lifetime)").
- **Cross-entity reachability.** Event drawer Lineage tab gains a "Properties reachable via joins" subsection, sourced from Cube `joins:` blocks.
- **PII → `public: false`.** PII chip on a property toggles `public: false` on the emitted dimension; downstream measures depending on it inherit a "private" badge.
- **Bidirectional lineage.** Drawer Lineage tab shows both upstream (cubes joined, views the event lives in) and downstream (artifacts that consume it).
- **Register screen surfaces the PR.** Submit opens the PR in a new tab; in-app shows status timeline + reviewer + checks.

---

## Executive Verdict (8 bullets — original + 2 amendments)

1. **Q1 — Semantic Enrichment:** Replace inline "edit description" on events.jsx with a **rich side-panel modal** (Mixpanel Lexicon pattern) that surfaces property-level metadata, ownership, PII tags, and "verified" checkmarks. Current demo is too shallow — PMs need a single source of truth for event meaning beyond description.

2. **Q1 Steal:** Adopt Mixpanel's **Data Standards compliance flags** — when a PM describes an event, auto-check against naming conventions, required fields (owner, domain), and mark visually as "compliant" or "fix me" with inline remediation. This costs 80 lines of React state; huge UX win.

3. **Q2 — Metric Definition Flow:** Current formula-bar + inputs A/B/C is genuinely elegant, but it assumes users already know *which measures* exist and can express the metric in math. **Layer a hybrid approach**: (1) event-picker → (2) semantic context (what does this event mean?) → (3) template suggestions → (4) formula if needed.

4. **Q2 Steal:** Add a **"Quick metrics" template menu** below the formula bar — 5–8 pre-built patterns (rate, average, conversion, retention, cohort-overlap) that auto-bind to the selected event's properties. Amplitude and Mixpanel do this silently; explicit templates accelerate first-time PMs.

5. **Q2 Risk:** Do NOT add AI/NL input ("describe the metric") yet. Hex Magic works because users write English descriptions of what they *already computed*; they don't reverse-engineer metrics from intent. Once you have 50+ metrics, consider NL-to-metric for power users, not first flow.

6. **Q1 & Q2 Synthesis:** Reorder the **events.jsx → formula.jsx flow** to (A) pick event, (B) enrich semantics inline, (C) suggest pre-built templates based on event type, (D) land in formula editor if PM wants custom math. Current demo skips (B) and (C); they're not "nice to have" — they unlock PM self-service.

7. **Property-Level Semantics:** In events.jsx properties table, add a third column for **property metadata chips**: [enum: {A, B, C}], [PII: email], [suggested measure], [deprecated]. Heap and PostHog surface this; it's critical for reducing wrong-metric definitions.

8. **Register Screen Signal:** Keep it as-is (SQL handoff is correct), but add a **"Is this a metric or property?" wizard** on formula.jsx before register. Current demo buries the choice; it should be prominent because semantic meaning (metric vs property) drives downstream ML/feature-store materialization. One wrong choice breaks the catalogue.

9. **(Addendum) Layer-1 Gap — Aggregation Primitives:** The demo cannot mint a new measure from a raw event. Insert a **Statsig-style primitive card grid** (Sum / Count / Unique Count / Ratio / Derived Ratio / Times-per-user) between `events.jsx` and `formula.jsx`. Each card opens a thin form (column + filter + optional per-user wrap) that emits a Cube `measure` block. ~250 LOC, new screen `measure.jsx`. This is the missing bridge that makes the formula-bar self-serve.

10. **(Addendum) Times-per-user is its own beast.** All other primitives are single-stage aggregations; "Times per user" is two-stage (per-user inner agg → across-users outer agg). It needs a dedicated card with two pickers (inner: count/sum/distinct; outer: avg/median/p95). Statsig has "User Aggregation"; Amplitude calls it "Per User"; in Cube terms it's a pre-aggregation grouped by `user_id` or a sub-query measure.

---

## Q1 Deep Dive — Semantic Enrichment Patterns

### Problem Statement
The demo has *minimal* semantic enrichment: event ID, description (editable inline), volume, usage count, raw properties table. Maturity gap vs. Mixpanel Lexicon, Amplitude Data Govern, Heap autocapture — which let non-technical users tag ownership, deprecation, PII, enums, and "verified" status.

### Best-in-Class Implementations

#### 1. **Mixpanel Lexicon + Data Standards (2025)** 
**What it does:** Central event dictionary with hierarchical metadata: event → properties → compliance rules.

**UX Pattern:**
```
Event: purchase_completed
├─ Display name (editable): "User Purchase"
├─ Description: "User completed a transaction."
├─ Owner: [Data Team] (dropdown)
├─ Domain: [Monetization] (tag)
├─ Verified: ✓ (compliance badge)
├─ Properties:
│  ├─ amount_local (required)
│  │  ├─ Type: number
│  │  ├─ Sample: 50000
│  │  ├─ PII tag: [Yes, currency]
│  │  ├─ Enum hint: {VND, USD, THB}
│  │  └─ Suggested measure: "sum(amount_local)"
│  ├─ currency
│  │  ├─ Type: string
│  │  ├─ Enum: [VND, USD, THB] (locked)
│  │  └─ Suggested measure: "count(distinct currency)"
```

**Why it works:**
- One event panel (not scattered across rows).
- Property-level metadata reduces metric-definition errors (no ambiguity on "is this a sum or count?").
- **Data Standards** auto-flag missing owner/description — Lexicon shows compliance at a glance.
- Ownership creates accountability.

**Source:** [Mixpanel Data Standards 2025](https://community.mixpanel.com/x/announcements/rf5qgmlgynth/enhance-data-governance-with-new-standards-feature)

---

#### 2. **Amplitude Data Govern** 
**What it does:** Event classification (tier: core/secondary/exploratory) + lineage to dashboards + impact analysis ("who uses this?").

**UX Pattern:**
- Event card shows: [Tier badge] [Owner avatar] [# of dashboards using it] [last updated date]
- Click → side panel with edit form + full revision history.
- Auto-detects "unused" events (no dashboard links) → soft-deprecation prompt.

**Why it works:**
- Tier system (core/secondary) makes it obvious what to optimize first.
- Impact analysis prevents breaking changes (you see who depends on this event).
- Revision history builds confidence ("did someone change this?").

---

#### 3. **Heap Autocapture + Data Lineage**
**What it does:** Auto-instrumented events (no schema definition needed) + retroactive property extraction + recommended measures.

**UX Pattern:**
- Event carousel: browse captured interactions (pageview, click, form_submit).
- For each: show live samples → "suggest taxonomy" button → AI proposes: "This looks like a funnel step; suggest measure = count(events)" → accept/reject.
- Properties tagged with ML-derived types: [probably PII], [probably a filter], [probably a dimension].

**Why it works:**
- Zero upfront instrumentation overhead (appeals to PM-led orgs).
- AI suggestions reduce metadata-entry friction.
- Measures are suggested, not required — users discover best practices over time.

**Trade-off:** Autocapture produces noise (every click is an event); governance must be active, not optional.

---

### Recommendation for Metrics Catalogue

**Adopt a fusion of Lexicon + Data Govern:**

1. **Event panel (right-side drawer):**
   - Tab 1: Metadata (description, owner, domain/category, tier: core/secondary/exploratory, verified Y/N)
   - Tab 2: Properties (table with 5 columns: name, type, sample, enum/range, suggested measure)
   - Tab 3: Lineage (which metrics/cohorts use this? quick links)
   - Tab 4: History (who edited, when)

2. **Inline compliance:**
   - Event row shows: [Prov dot] [Owner initials] [Status: ✓ verified | ⚠️ incomplete | ⛔ deprecated]
   - Hovering reveals reason (missing owner, no description, etc.)

3. **Property-level enrichment:**
   ```jsx
   <tr key={p.name}>
     <td><PropType type={p.type} /> {p.name}</td>
     <td>{p.sample}</td>
     <td>
       <Badge variant="outline">{p.type}</Badge>
       {p.isEnum && <Chip>enum: {p.enumValues.join(', ')}</Chip>}
       {p.isPii && <Chip variant="warn">PII</Chip>}
       {p.suggestedMeasure && <Chip variant="info" onClick={...}>Measure: {p.suggestedMeasure}</Chip>}
     </td>
   </tr>
   ```

4. **Not required yet:** Governance rules (Data Standards), revision history. Ship tabs 1–3 first. History can wait.

---

## Q2 Deep Dive — No-Code Metric Definition Flows

### Problem Statement — restated as three layers
Metric authoring is **not one act**. It's three layers stacked:

1. **Layer 1 — Aggregation primitive:** turn a raw event/column into an atomic measure (`sum(amount_local) on purchase_completed`). Output = a Cube `measure` block.
2. **Layer 2 — Composition:** combine measures with operators (`whale_recharged_7d / whale_users`). Output = a derived metric.
3. **Layer 3 — Template:** pre-package layers 1+2 for known patterns (funnel, retention).

Current demo only exposes Layer 2 (formula-bar) and Layer 3 (hidden in a dropdown). **Layer 1 is missing entirely** — the demo's `measures` list is hardcoded; a PM cannot create a new one. This is the most-cited reason non-tech users abandon Looker/Omni-style tools: the formula presupposes a measure library someone else built.

Maturity gap: Amplitude, Mixpanel, PostHog, Statsig skip the math for most use cases. They offer **primitive cards → visual/template-driven flows** first, **formula** as an escape hatch.

### Pattern Comparison

#### **Pattern 0 (Addendum): Aggregation Primitives (Statsig, Heap, Mixpanel Custom Events)**

**The screenshot the user shared (Statsig metric type picker):**
```
┌─ Sum ─────────────────┐  ┌─ Count ──────────────────┐
│ Total of a numeric    │  │ Number of rows matching  │
│ column                │  │ a condition              │
└───────────────────────┘  └──────────────────────────┘
┌─ Ratio ───────────────┐  ┌─ Derived Ratio ──────────┐
│ One metric divided    │  │ Ratio computed from two  │
│ by another            │  │ columns in same table    │
└───────────────────────┘  └──────────────────────────┘
┌─ Unique Count ────────┐  ┌─ Times per user ─────────┐
│ Count of distinct     │  │ Per-user agg → across-   │
│ values in a column    │  │ user agg (avg/p50/p95)   │
└───────────────────────┘  └──────────────────────────┘
```

**How it works:** PM picks an event → picks a primitive card → fills 1–2 fields → primitive registers as a Cube `measure` → primitive becomes available in formula-bar's A/B/C dropdown.

**Mapping to semantic layer YAML (this is what makes it real, not a toy):**

| Card | Inputs | Cube YAML | dbt MetricFlow |
|---|---|---|---|
| **Sum** | numeric column, filter? | `type: sum, sql: amount_local` | `agg: sum, expr: amount_local` |
| **Count** | filter? | `type: count` | `agg: count` |
| **Unique Count** | dedupe column, filter? | `type: count_distinct, sql: user_id` | `agg: count_distinct, expr: user_id` |
| **Ratio** | numerator measure, denominator measure | `type: number, sql: "{m_num}/{m_den}"` | metric: `ratio` with `numerator`/`denominator` |
| **Derived Ratio** | numerator column, denominator column (same table), filter? | `type: number, sql: "SUM(a)/NULLIF(SUM(b),0)"` | inline `expr` |
| **Times per user** | inner agg (count/sum/distinct), outer agg (avg/median/p95), filter? | sub-query measure or pre-agg grouped by `user_id` | `agg_time_dimension` + outer agg |

**Who it's for:** PMs, growth analysts, anyone who can answer "are you adding numbers up, or counting rows?". This is the floor — below this is SQL.

**Elegance score:** 9/10 (Statsig's card grid). 6/10 in Mixpanel/Amplitude where it's buried in a dropdown.

**What to steal:**
- **Promote primitive choice to its own screen.** Don't bury it in a dropdown. The decision (sum vs count vs unique count) drives everything downstream.
- **Two fields max per primitive.** Sum = column + filter. Count = filter. Unique Count = dedupe column + filter. More than two fields kills the "feels easy" effect.
- **Live value preview** on the primitive screen — same pattern as `formula.jsx` preview block but for the just-defined measure.
- **"Times per user" gets a dedicated card** — don't try to bolt two-stage agg onto Sum/Count. Different mental model.
- **Auto-derive measure name** from primitive + column (`sum_amount_local`, `count_purchase_completed`, `unique_users_purchase_completed`). PM can edit.

**Trade-off:** Adds a screen to the flow. But it's the screen that lets PMs *self-serve* — without it, every new metric requires a data engineer to write a Cube measure first.

**Sources:**
- [Statsig metric types](https://docs.statsig.com/metrics/metric-types/) — Sum / Count / Ratio / Derived Ratio / Unique Count / User Aggregation
- [Cube measures reference](https://cube.dev/docs/reference/data-model/measures) — `type` values: `count, sum, avg, min, max, count_distinct, count_distinct_approx, number`
- [dbt MetricFlow measures](https://docs.getdbt.com/docs/build/measures) — `agg: sum | count | count_distinct | average | min | max`
- [Heap Defined Events + Recommended Measures](https://help.heap.io/) — primitive picker hidden in "Add a measure" dropdown

---

#### **Pattern 1: Formula-bar (Current Demo, also Looker, Omni, Mode)**

**How it works:**
- User picks inputs (A=whale_users, B=whale_recharged_7d)
- Writes formula: B / A
- Result updates live
- Auto-detects output type (ratio, count, percent)

**Who it's for:** Analysts, power-PM users, people comfortable with algebra.

**Elegance score:** 8/10 (formula is honest, direct, previews live)

**What to steal:**
- Live result preview (your demo does this ✓)
- Auto-type detection (your demo does this ✓)
- Letter-based inputs (A, B, C) with color-coding (your demo does this ✓)
- Template shortcuts (B / A = "rate", etc.) — **your demo does this ✓**

**Trade-off:** Assumes PM knows which measures exist. If there are 50 measures, discovery is painful.

---

#### **Pattern 2: Template-Driven (Statsig, Eppo, PostHog Experiments)**

**How it works:**
```
Select metric type: [Funnel] [Retention] [Conversion] [Custom count] [Custom ratio]
├─ If Funnel:
│  ├─ Event A (step 1): [pick_from_list]
│  ├─ Event B (step 2): [pick_from_list]
│  ├─ Time window: [1 day] [7 days] [custom]
│  └─ Preview chart → done
├─ If Conversion:
│  ├─ Success event: [pick]
│  ├─ Denominator: [all events] [users] [cohort]
│  └─ Filters: [optional]
```

**Who it's for:** PMs running experiments, non-data-literate teams, fast metrics.

**Elegance score:** 7/10 (constrained, reduces mistakes, but sometimes too rigid)

**What to steal:**
- Pre-filled templates for common patterns (funnel, retention, cohort-overlap).
- Step-by-step wizard (not "throw everything at the user").
- Filters panel (Statsig shows "segment by X" — critical for subgroup metrics).

**Trade-off:** 20% of metrics won't fit a template; users get frustrated and demand "custom formula" anyway.

---

#### **Pattern 3: Visual Pipeline (Amplitude, Mixpanel Create Metric)**

**How it works:**
```
[Event picker] → [Filter builder] → [Aggregation picker] → [Time window] → [Compare groups] → [Save]

Step 1: Select base event
  - Browse or search event list
  - Preview sample values & volume
  
Step 2: (Optional) Apply filters
  - "Only count if property = X"
  - "Exclude bots"
  
Step 3: Choose aggregation
  - Count (unique users)
  - Sum (of property Y)
  - Average (of property Y)
  - Funnel (event A → B → C)
  
Step 4: Time window
  - Last 7 days, Last month, Custom
  
Step 5: (Optional) Compare groups
  - By platform, by country, etc.
  
Step 6: Name & save
```

**Who it's for:** PMs, marketers, growth analysts. Majority of metrics are "count distinct users who did X with filter Y."

**Elegance score:** 9/10 (reduces complexity, guides without forcing formula)

**What to steal:**
- Event picker as step 1 (your demo puts this as a separate route; integrate it).
- Filter builder (your demo has measure-level filters only; add event-property filters).
- Aggregation picker (explicit "sum vs count vs average" — your demo buries this in input binding).
- Wizard layout (linear, breadcrumbs, not all options at once).

**Trade-off:** Steeper UX (more steps), but dramatically lower error rate for first-time users.

---

#### **Pattern 4: Composable Building Blocks (dbt MetricFlow, GoodData MAQL, Cube Views)**

**How it works:**
```
Metric = Measure + Dimensions + Filters + Aggregation

base_metric = sum(revenue) / count(distinct users)
revenue_per_user = base_metric
whale_revenue = revenue_per_user where spend_tier = 'whale'
weekly_whale_revenue = whale_revenue grouped by week
```

**Who it's for:** Data engineers, advanced analysts. Requires understanding of data model (entities, measures, dimensions).

**Elegance score:** 10/10 for experts, 3/10 for PMs (high floor).

**What to steal:**
- Composability (can you define "whale_users" once and reuse it?). Your demo pre-loads cohorts like "whale_users" — this pattern.
- Semantic clarity (measures, dimensions, filters are named concepts, not just letters A, B, C).

**Trade-off:** Requires semantic layer maturity (data team must have defined measures, dimensions upfront). Chicken-and-egg problem for new orgs.

---

#### **Pattern 5: AI / NL-to-Metric (Hex Magic, Cortex Analyst, SearchIQ)**

**How it works:**
```
User says: "Give me weekly revenue for whales vs non-whales"

AI:
1. Parses intent: metric = revenue, grouped by spend_tier, time_period = week
2. Finds matching measures: (sum of revenue by user)
3. Generates SQL or formula
4. User reviews, accepts, or requests edits
5. Metric auto-registers
```

**Who it's for:** C-suite, PMs with low data literacy. Requires 50+ existing metrics (LLM needs training data).

**Elegance score:** 9/10 for polished intent, but high failure rate on first try.

**What to steal:**
- Only after you have 50+ validated metrics.
- Even then, restrict to "refine existing metrics" (e.g., "add a filter to X"), not "define new metrics from scratch."
- NL is best as a **discovery aid**, not definition: "show me metrics that measure revenue by cohort" → user picks "whale_revenue" → user edits it.

**Trade-off:** Garbage-in-garbage-out. If your metric definitions are noisy, AI magnifies it. Wait until Q1 (semantics) is rock-solid.

---

### Recommended Hybrid for Your Prototype

**Flow: Event-Pick → Semantics → Primitive → Template or Formula → Preview → Register**

```jsx
// Phase 1: User decides what they're measuring
Route: "events"
└─ Browse event list (events.jsx — existing screen, plus "Rich edit" drawer)
└─ Select event → CTA "Define measure on this event" → go to Phase 2

// Phase 2: User enriches the base event meaning (Q1 — Mixpanel Lexicon)
Route: "events" (drawer)
└─ Side drawer with tabs:
   ├─ Metadata (description, owner, domain, tier, verified)
   ├─ Properties (name, type, sample, metadata chips: enum/PII/suggested-measure)
   └─ Lineage (which metrics use this event)

// Phase 2.5: User picks an aggregation primitive (ADDENDUM — Statsig pattern)
Route: "measure" (NEW screen — measure.jsx)
└─ Card grid (6 cards):
   ├─ Sum            → pick numeric column, optional filter
   ├─ Count          → optional filter
   ├─ Unique Count   → pick dedupe column, optional filter
   ├─ Ratio          → pick numerator measure + denominator measure
   ├─ Derived Ratio  → pick numerator column + denominator column, optional filter
   └─ Times per user → inner agg (count/sum/distinct) + outer agg (avg/p50/p95)
└─ Form (right pane): primitive-specific fields + live value preview
└─ Auto-derived name + Cube YAML preview (read-only)
└─ "Register measure" → measure appears in formula.jsx A/B/C dropdown
   OR
└─ "Use in metric formula" → seeds Phase 3 with this measure as input A

// Phase 3: User composes (Layer 2 — formula-bar; or Layer 3 — template)
Route: "formula"
└─ Top tabs: [Templates] | [Custom formula]
   ├─ Templates tab (Layer 3 — promoted from dropdown):
   │  ├─ [Daily active users]
   │  ├─ [Conversion funnel]
   │  ├─ [Retention curve]
   │  ├─ [Cohort overlap]
   │  └─ Pick → auto-fill formula + inputs → Preview
   │
   └─ Custom formula tab (Layer 2 — current demo):
      ├─ Inputs A/B/C (now include measures minted in Phase 2.5)
      ├─ Formula bar + operators
      └─ Preview

// Phase 4: Mode decision (promoted from "Identification" section)
Route: "formula"
└─ "Metric or Property?" — prominent radio with examples
   ├─ Metric: one number per query (registers as Cube measure on a view)
   └─ Property: per-event/per-user value (registers as Cube dimension or user trait)

// Phase 5: Register (unchanged)
Route: "register"
└─ Same as current (SQL, classification, submit)
```

**The critical insight:** Phase 2.5 (measure.jsx) is the bridge that makes Phase 3 self-serve. Without it, the formula-bar only knows the measures someone else pre-baked. With it, a PM can: (a) pick `purchase_completed`, (b) define `sum(amount_local)` as a primitive measure, (c) use that measure as input A in a formula `A / B` where B is `unique_users(purchase_completed)` — both minted in the same session, without a DE.

---

## Concrete UI Deltas Table

### How to Read This
- **Today (demo):** What the prototype currently shows
- **Recommended:** Specific change + source pattern
- **Lines of code (est.):** Effort to implement as JSX edits

| # | Surface | Today (demo) | Recommended | Source Pattern | LOC |
|----|---------|------------|------------|--------------|-----|
| 1 | **Events.jsx: Event Detail Panel** | Inline edit button on description; limited metadata | **Rich side-drawer** with tabs: Metadata / Properties / Lineage. Tabs 1 & 2 required, Tab 3 optional. | Mixpanel Lexicon | 180 |
| 2 | **Events.jsx: Event Row** | [Prov dot] [Event name] [Badges: sampled, volume, usage] | **Add owner initials + status badge** (✓ verified \| ⚠️ incomplete). Hover reveals remediation action. | Amplitude Data Govern | 40 |
| 3 | **Events.jsx: Property Table** | [Name] [Sample] [Type badge] | **[Name] [Sample] [Type badge] [Metadata chips]** where chips = [enum: {A,B,C}], [PII: tag], [measure: suggestion]. Add click-to-copy-measure-ref. | Heap autocapture + Mixpanel | 120 |
| 4 | **Events.jsx: New Button** | "Bulk import" / "Governance" in toolbar | **"Rich edit" button** → opens semantic enrichment panel. "Governance" navigates to compliance checklist. | Mixpanel Data Standards | 20 |
| 5 | **Formula.jsx: Pre-Entry Flow** | User lands directly at input picker | **Add "Pick an event first" route** (copy from events.jsx, add "Define metric" CTA). Breadcrumb: Home / Metrics / [event] / New metric | Amplitude path | 100 |
| **5a** | **NEW Screen: measure.jsx — Primitive Picker** | N/A — demo cannot mint a new measure | **Statsig-style 6-card grid** (Sum / Count / Unique Count / Ratio / Derived Ratio / Times-per-user). Each card opens a thin form on the right pane: column picker + optional filter + live value preview + auto-generated name + Cube YAML preview. CTA: "Register measure" or "Use in metric formula". | Statsig metric types | 250 |
| **5b** | **Events.jsx: Action Grid** | `[Funnel][Cohort][Flow][Metric]` | **Replace `[Metric]` with `[Define a measure]`** — routes to measure.jsx with selected event pre-bound. Keep Funnel/Cohort/Flow. | Statsig pattern | 10 |
| 6 | **Formula.jsx: Semantic Context Prompt** | N/A | **Show event summary + optional semantic enrichment inline** before formula bar. "Is this the right event? Edit description, owner, or filters." | Pattern: Linear wizard | 80 |
| 7 | **Formula.jsx: Template Row** | Templates hidden in dropdown (zap icon) | **Promote to prominent tabs** above formula bar: `[Templates]` `[Custom formula]`. Inside Templates: [Daily active users] [Conversion rate] [Retention] [Funnel]. | Statsig / Eppo metrics | 60 |
| 8 | **Formula.jsx: Input Binding** | A/B/C letter chips; users pick measures manually | **Add inline filter builder** for each input. "whale_users where spend_tier = whale" → show property-level filters (not just measure-level). | Amplitude visual pipeline | 140 |
| 9 | **Formula.jsx: Mode Toggle** | Hidden in "Identification" section | **Promote to prominent section BEFORE formula input** ("Metric or Property?"). Explain difference with examples. | Current demo (unclear visibility) | 30 |
| 10 | **Formula.jsx: Quick Actions** | "Discard" / "Save draft" / "Register metric" in header | **Add "Auto-generate from template" CTA** if formula is empty. "Suggest name from event" auto-fill. | Amplitude / Mixpanel UX | 50 |
| 11 | **Register.jsx: Complexity Check** | User submits; SQL shows up | **Pre-register checklist** on formula.jsx (before redirect to register): "Is this a metric (one-number output) or property (per-event output)? One wrong choice breaks the catalogue." Require explicit choice. | Best practice | 60 |
| 12 | **Register.jsx: Similar Metrics** | Shows 3 hardcoded similar metrics | **Dynamically compute similarity** based on formula + base event + filters. Show 3–5 actual similar metrics from library; let user view before submitting. | Current demo + Lightdash pattern | 80 |

**Total LOC estimated:** ~1,260 (1–2.5 weeks, JSX-only edits; no backend changes needed for demo). Bulk of new code: measure.jsx (~250) + events.jsx drawer (~180) + formula.jsx primitive integration + template tabs (~140) + property metadata chips (~120).

---

## Architectural Fit Assessment

### Current Demo Stack
- Single-page React app on CDN (Vite/React 18)
- Client-side state (React hooks)
- Mock data in window.MC_DATA
- No backend yet (registration is stub)

### Recommendations Compatibility
1. **Semantic enrichment UI (deltas 1–4, 6, 9):** Pure JSX. No backend changes. Add state to event panel for edit mode, owned/verified/tier fields. ✓ **Ready now.**
2. **Template-driven flow (deltas 5, 7, 10):** Requires pre-loaded template definitions. Can live in data.js. ✓ **Ready now.**
3. **Property-level filters (delta 8):** Requires property definitions to include enum values / suggested filters. Update data.js schema. ✓ **Ready now.**
4. **Similarity scoring (delta 12):** Requires metric definitions in data.js + simple string-distance algorithm (Levenshtein or TF-IDF on formula). ✓ **Ready now, but cosmetic until register is hooked to real backend.**

### Risk / Complexity

**Low risk:**
- All UI changes (panels, tabs, tabs icons, filters).
- Data model changes (add owner, tier, enum, pii fields to events).

**Medium risk:**
- Template system (must define 5–8 templates, test auto-fill).
- Filter UI (must handle property types: string with enums vs numbers vs dates).

**Not in scope for this prototype:**
- Metric similarity scoring against real library (wait for backend).
- Governance rules enforcement (Data Standards).
- Revision history / lineage (nice-to-have).

---

## Summary of Unresolved Questions

1. **Who owns events?** Recommend adding a real owner field (user ID or team ID), but demo can stub as "Data Team" or "PM Name". Should ownership be required or optional on register? → **Decision: optional for beta, required for prod.**

2. **How do "tier" (core/secondary/exploratory) and "verified" status interact?** Can a secondary event be verified? Should only core events appear in the "quick templates"? → **Decision: tier is maturity (core = production-ready); verified is compliance (owner + description present). Independent states.**

3. **When should suggested measures appear?** On event view, or only in template flow? If PM is defining a custom formula, should they see "suggested: sum(amount_local)" on the input picker? → **Decision: Show on both. Non-intrusive chips; users ignore if not helpful.**

4. **How to handle metric composition?** Current demo allows measure-on-measure formulas (whale_users / total_users). Should the system prevent composing computed metrics (metric on metric)? Or encourage it? → **Decision: Allow for now (composability is powerful), but surface a warning ("This is a secondary metric") on register.**

5. **Property-level enums:** Should the system auto-detect enums from sample data? Or require data team to declare them? → **Decision: For demo, hardcode (currency: {VND, USD}, sku: {...}). For prod, either auto-detect or integrate with dbt/Cube metadata inference.**

6. **AI/NL input:** Should the prototype include a "describe your metric in English" field on formula.jsx? → **Decision: Not yet. Ship Q1 (semantics) + Q2 (template/formula) first. NL is a v2 feature post-50-metrics.**

7. **Property-level filters on inputs:** Current demo shows measure-level filter text ("spend_tier_lifetime = whale"). Should users build filters visually (pick property, operator, value) or write expressions? → **Decision: Visual filter builder (property picker → operator {=, >, <, in} → value) for first iteration. SQL expressions as an escape hatch.**

8. **(Addendum) Times-per-user materialization in Cube.** → **RESOLVED 2026-05-14 16:51 — pre-aggregation grouped by `user_id`.** Card form code-gens a `pre_aggregations:` block; inner agg becomes a measure on the pre-agg, outer agg becomes a measure that reads from the pre-agg. See "Resolved Decisions" table at the top of this report.

9. **(Addendum) Measure-vs-metric vocabulary.** → **RESOLVED 2026-05-14 16:51 — separate for clarity.** Layer 1 = "measure" (Cube atom); Layer 2 = "derived metric" (`type: number` over measure refs). UI labels everywhere enforce the split. See "Resolved Decisions" table at the top of this report.

---

## References & Sources

- [Mixpanel Lexicon Documentation](https://docs.mixpanel.com/docs/data-governance/lexicon)
- [Mixpanel Data Standards 2025](https://community.mixpanel.com/x/announcements/rf5qgmlgynth/enhance-data-governance-with-new-standards-feature)
- [dbt MetricFlow Documentation](https://docs.getdbt.com/docs/build/about-metricflow)
- [dbt MetricFlow Measures](https://docs.getdbt.com/docs/build/measures)
- [Cube.dev Semantic Layer & Visual Designer](https://cube.dev/use-cases/semantic-layer)
- [Cube Measures Reference](https://cube.dev/docs/reference/data-model/measures) — `type` values catalog
- [Statsig Metric Types](https://docs.statsig.com/metrics/metric-types/) — primitive card grid (Sum / Count / Ratio / Derived Ratio / Unique Count / User Aggregation)
- [Hex AI Analytics Overview](https://hex.tech/)
- [Amplitude vs Mixpanel vs Heap 2026 Comparison](https://www.techno-pulse.com/2026/05/best-ai-product-analytics-tools-in-2026.html)

---

**Report Status:** DONE (patched 2026-05-14 15:59 with Layer-1 addendum)
