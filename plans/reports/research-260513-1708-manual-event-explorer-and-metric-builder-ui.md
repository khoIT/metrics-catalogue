# Research Report — Manual Event Explorer + No-Code Metric Builder UI

> **Date:** 2026-05-13 17:08 (Asia/Saigon)
> **Author:** researcher
> **Scope:** Phase-1 product layer for non-technical users to (1) manually explore raw events, (2) build cohorts/funnels/retention/flows over them, (3) define new metrics via a no-code formula builder, (4) save those metrics into a registered Feature Store. Agent/AI flow is **out of scope** (Phase 2). Hermes patterns referenced conceptually only — no source-code references.
> **Deliverable shape:** landscape scan first, ASCII wireframes second. Designer-portable. Examples anchored on VNG Games CFM data; principles are generic.

---

## Table of Contents

**Part A — Landscape Scan**
- A.1 The job-to-be-done (precise)
- A.2 Vocabulary primer (for designers)
- A.3 The two-grain data model
- A.4 The five primitives that matter
- A.5 Mixpanel / Amplitude / PostHog patterns worth stealing
- A.6 No-code formula builder — the Mixpanel pattern, dissected
- A.7 Metric registration — what Hermes Feature Store teaches us
- A.8 Provenance, trust, data quality
- A.9 Anti-patterns (don't do these)

**Part B — UX Brief & Wireframes**
- B.1 Information architecture
- B.2 Landing / Home
- B.3 Event Explorer (data dictionary)
- B.4 Funnel Builder
- B.5 Cohort Builder
- B.6 Retention Chart
- B.7 Flow / Path Analysis
- B.8 Formula Builder (no-code metric authoring)
- B.9 Save & Register a Metric (handoff modal)
- B.10 Metric Library (post-registration browse)
- B.11 Metric Detail (post-registration deep dive)
- B.12 Copy guidelines (microcopy & vocabulary)
- B.13 Empty / loading / error states
- B.14 Build sequencing & cut lines

**Part C — Risks & Open Questions**

---

# Part A — Landscape Scan

## A.1 The job-to-be-done (precise)

> **A LiveOps PM (or generic non-technical product manager) walks in cold. They have a hunch — "I think CFM whales are dropping off faster than mid-tier players after the Tet event." They want to:**
> 1. Confirm or kill the hunch by poking at real event data, without writing SQL.
> 2. If the hunch holds, codify the pattern into a reusable metric.
> 3. Hand that metric to engineering with everything they need to ship it for real.

That's the entire product. Everything else is feature creep.

**What this is NOT:**
- A dashboard builder (Tableau, Looker territory — `/canvas`-style pinning is downstream)
- A SQL IDE (Cube Playground exists; engineers can use it)
- An AI chat surface (Phase 2)
- A campaign authoring tool (`/segments` and `/campaigns` already exist in Hermes)

## A.2 Vocabulary primer (for designers)

| Term | Plain-English meaning | UI implication |
|---|---|---|
| **Event** | One thing a user did (one row in the events table). "user_456 paid 50,000 VND at 14:32". Has a name + timestamp + properties | Surface as a list with type icon |
| **Property** | A field attached to an event ("amount", "currency", "level") or a user ("region", "vip_status") | Surface as filterable, with type icon (#, A, ✓, 📅) |
| **Cohort** | A group of users who share a behavior or trait | The thing you build with the Cohort Builder |
| **Metric** | A number you can chart over time. "DAU", "ARPDAU", "30-day retention" | The output of the Formula Builder; the thing that lands in Feature Store |
| **Funnel** | An ordered sequence of events you want users to complete (step 1 → 2 → 3) with drop-off % at each step | Multi-step wizard with drop-off bars |
| **Retention** | "Of users who did X on day 0, what % did Y by day N?" | Heatmap (rows = cohorts, columns = days) |
| **Flow / Path** | The actual sequences users take from or to a chosen event | Sankey diagram |
| **Feature** (Hermes term) | Same as **Metric** in this report. The thing PMs shop for in the Feature Store. Use "Metric" in PM-facing copy, "Feature" only when bridging to Hermes |

**Hard rule for microcopy:** PMs see **Metric** everywhere. Engineers see **Feature** only on the bridge surfaces (handoff modal, lineage view). One word per audience.

## A.3 The two-grain data model

The explorer must speak two grains of data because the underlying business questions live at two grains:

| Grain | Source | Latency | Primitives it powers |
|---|---|---|---|
| **Daily-aggregate** (one row per user per day) | Pre-aggregated cubes (active_daily, recharge, mf_users, user_recharge_daily) | <1s warm | Cohort, Retention, distribution exploration |
| **Raw event** (one row per event) | Trino `ballistar_vn.events` (billions of rows) | seconds–minutes | Funnels, Flows, event property exploration |

**Design implication:** the UI must signal which grain a question runs against, because **latency expectations differ by an order of magnitude**. A cohort over daily aggregates returns in <1s; a 5-step funnel over raw events might take 8–15s.

**Recommended pattern (borrowed from Hermes provenance):** every chart shows a small footer:

```
🟢 Daily aggregate · cube: user_360 · last refresh 14:02 · 200ms
```
or
```
🟠 Raw events · trino: cfm_vn.events · 312M rows · 8.4s
```

The colored dot is the trust signal. Green = fast + fresh + complete. Amber = slow + heavy + may sample.

## A.4 The five primitives that matter

Across Mixpanel, Amplitude, PostHog, Heap, June — the **same five primitives** show up. Non-technical users in 2026 still rely on the same shapes Amplitude shipped in 2014, because they map cleanly to the questions PMs actually ask.

| # | Primitive | Question it answers | Grain |
|---|---|---|---|
| 1 | **Event Explorer** (data dictionary) | "What can I even look at?" | Both |
| 2 | **Funnel** | "Where do users drop off in a sequence?" | Raw |
| 3 | **Cohort** | "Who are the users that did X?" | Both (daily preferred for size, raw for behavioral) |
| 4 | **Retention** | "Do users come back?" (day-N retention) | Daily |
| 5 | **Flow / Path** | "What do users actually do, in what order?" | Raw |

**Plus the bridge primitive:**

| # | Primitive | Question it answers |
|---|---|---|
| 6 | **Formula Builder** | "Now turn this into a number I can chart and reuse" |

The whole product is these six things. If you ship them well, you're done.

## A.5 Mixpanel / Amplitude / PostHog patterns worth stealing

### Funnel — the canonical patterns

- **Conversion-window picker.** PostHog defaults to 14 days; Mixpanel/Amplitude similar. Make it prominent — wrong windows produce wrong answers.
- **Two views of drop-off.** "Overall (vs step 1)" and "Step-over-step (vs previous step)." Toggle, not a sub-menu.
- **Absolute and relative.** Show both `12,481 users lost · 23.2%`. PostHog explicitly recommends prioritizing by absolute drop-off (a 30% loss out of 10,000 beats a 50% loss out of 500). Most tools bury absolute counts — surface them.
- **Between-step filters.** "Step 2 must happen *with* property X = Y." Not a separate where-clause panel — inline filter chips on each step.
- **Cohort segmentation overlay.** Compare two cohorts' funnels in the same chart (e.g., whales vs free, VN vs TH). Solid line vs dashed.

### Cohort — boolean composition done right

Amplitude's canonical pattern (also adopted in Hermes Segments composer):

```
Users WHO did [event ▼] [≥ 1 time ▼] in [last 30 days ▼]
  WITH property [region = VN ×]
  AND [event ▼] [...] [...]
   OR [event ▼] [...] [...]
```

- **AND-of-OR** structure. AND is the top-level glue; OR groups nest inside. Trying to support full boolean (NOT, nested AND inside OR) is a rabbit hole that confuses PMs.
- **Live audience-count.** Re-runs on every change. Shows `33,813 users · 153ms` under the builder. Borrowed from Hermes' ThresholdPlayground pattern — generalize to multi-clause.
- **Exclusion rules.** "Users who did X but NOT Y" — common ask. Surface as a separate "Exclude" section so PMs don't have to think about boolean negation.
- **Save & reuse.** A cohort isn't just for the current question — it's a saved object that can be the cohort filter on funnels, retention, etc. The save modal is the bridge.

### Retention — what works

- **Day-N heatmap.** Rows = cohorts (acquisition week), columns = days/weeks since acquisition. Color shade = retention %. Mixpanel uses purple gradient; Amplitude uses orange. Pick one brand color, gradient by saturation.
- **N-day vs unbounded vs bracket retention.** Different definitions of "returning." Default to **bracket retention** (returned on day N specifically) for PM intuition; offer unbounded as a toggle.
- **Curve view.** Below the heatmap, a line chart of retention curves (one line per cohort) makes the trend obvious. Both views, one screen.
- **Cohort filter.** Apply a saved Cohort to filter who counts as "acquired." This is the wiring that makes #3 and #4 multiply in value.

### Flow / Path — Sankey or nothing

- **Sankey diagram** is the only visualization that works. Tree views and tables fail to communicate flow.
- **Forward and backward.** "What do users do AFTER X" and "What did they do BEFORE Y." Two modes, same chart.
- **Session window.** Default 30 minutes (Mixpanel/Amplitude/PostHog convention). Funnel uses days, Flow uses minutes — don't unify.
- **Limit visual complexity.** Cap at 5–7 step-columns; collapse small flows into "Other (N events)." Otherwise it's spaghetti.

### Event explorer — the data dictionary

This is the **most under-built** surface in most analytics products and the **most important** one for non-tech users. They cannot explore what they cannot find.

Mixpanel's **Lexicon** is the gold standard:
- Centralized list of all events + properties
- Display names (PM-friendly) override raw event names
- Descriptions are editable by non-developers
- Properties show **type icons** (number, string, boolean, datetime)
- Sample values inline (saves a query)
- "Used in N reports" usage count signals popularity

Amplitude's **Data** module takes governance further (bulk delete/block, active/inactive flags) but trades editing flexibility — Amplitude does NOT allow re-naming old events. **Mixpanel's editable display-name model is the right call for PM-facing UX.**

## A.6 No-code formula builder — the Mixpanel pattern, dissected

Mixpanel's Custom Properties + Formulas is the most copied no-code metric authoring UX. Here's the breakdown:

### Two distinct primitives, separate surfaces

| Surface | Purpose | When PM uses it |
|---|---|---|
| **Custom Property** | Compute a new property on each event/user from existing properties. E.g., `revenue_usd = amount * fx_rate` | Per-event derivation |
| **Formula (saved)** | Combine query-level results into a new metric. E.g., `ARPDAU = revenue / DAU` where revenue and DAU are themselves measures | Per-report metric |

For our v1 we conflate both into one **Formula Builder** with two modes (Property vs Metric). Modal split confuses; mode-toggle works.

### The interaction model

1. **Pick inputs.** Drag in 1–N existing measures/properties. Each gets a letter: A, B, C…
2. **Write the formula.** Excel-like syntax in a formula bar: `(A - B) / B * 100`. Operators: `+ - * / %`. `Ctrl+Space` for autocomplete of available functions.
3. **Preview.** Live numeric result against current filters + a chart preview. Critical — without this, PMs second-guess.
4. **Name & describe.** Plain English name, snake_case ID auto-generated.
5. **Save (scope choice).** Local to current report OR shared across project. Default local; the "Share" action is the bridge to Feature Store registration.

### What to add that Mixpanel doesn't have

- **Operator chips for non-formula users.** Below the formula bar, "Add: + Sum / − Subtract / × Multiply / ÷ Divide / % Percentage / Δ Change vs prior period." Click to insert at cursor. PMs allergic to text editors can build entirely via clicks.
- **Templates.** "Conversion rate (B/A * 100)", "Growth rate ((B-A)/A * 100)", "ARPU (revenue / users)". Pre-filled formulas the PM picks from a list.
- **Unit awareness.** PMs label inputs with units (count, currency, percent, ratio). The builder rejects nonsense (`currency * currency`) with a friendly "Hmm, multiplying VND by VND gives VND² — did you mean to divide?"

### What to NOT support in v1

- Window functions, lag/lead, conditional aggregation — these are real ask but they 10x the surface area. Defer to Phase 2.
- Sub-queries / nested formulas referencing other formulas — eventual yes, not v1.
- Custom SQL escape hatch — defeats the purpose.

## A.7 Metric registration — what Hermes Feature Store teaches us

Hermes Feature Store is the **destination** for any metric a PM authors. Borrow the registration mental model without borrowing the code:

### What the Feature Store contract requires for any new metric

| Field | Source | PM input style |
|---|---|---|
| Display name | PM types | "Whale 7-day Recharge Rate" |
| Mono ID | Auto-generated from display name | `whale_recharge_rate_7d` (PM can edit) |
| Domain | Picker from existing taxonomy | "Monetization" |
| Type | Auto-inferred from formula output | "number · ratio · 0–1" |
| Latency tier | PM picks | Realtime / Batch warm / Batch cold |
| Games | Multi-select (auto-suggests from explorer filter) | [CFM] |
| Description | Free text, 280 char cap | "Among users with spend_tier_lifetime = whale, the % who recharged in the last 7 days." |
| Use case (NEW) | Free text — why does the PM want this? | "Targeting churn-risk whales for the rescue campaign." |
| Underlying definition | Auto-generated from formula | dbt SQL scaffold + cube YAML proposal |
| Provenance / health | Empty on Day 0; populated after backfill | "Pending warm-up · 7 days" |

### The Hermes 3-persona tab pattern — adopt as-is for metric detail

Once a metric is registered, the Detail page presents three tabs reading the same metric from three audiences. Adopt verbatim:

| Tab | Audience | Surfaces |
|---|---|---|
| **LiveOps** | The PM who shops for metrics | Provenance dot, health verdict, threshold playground, "Use in segment" CTA |
| **Analyst** | Mid-tier user wanting distributions | Quantile strip, sample values, correlated metrics, outliers, cohort breakdown |
| **Engineer** | Owner of the materialization | Lineage (upstream tables + downstream consumers), pipeline run timeline, cost & latency, backfill history |

For a v1 **metric authoring** flow, only the LiveOps tab needs to be live after Save. Analyst and Engineer tabs populate after first backfill (with empty states until then).

### The handoff modal — the engineering signal

When a PM clicks "Register metric", a modal pops with:
- The PM's name + use-case + intended freshness
- The auto-generated SQL scaffold (read-only, but engineer can copy)
- A queue entry ("This metric will be reviewed by data engineering. ETA: 2 business days")
- A status badge that flips: `requested` → `in_review` → `building` → `active`

This is the bridge from "PM is poking" to "engineering ships." It's the most important step in the whole product. Without it, the explorer is a toy.

## A.8 Provenance, trust, data quality

Borrow Hermes' three-dot provenance system universally:

| Dot | Meaning | Where it shows |
|---|---|---|
| 🟢 **Green** | Real data, fresh, all rows present | Every chart, every metric in the library |
| 🟠 **Amber** | Real data BUT sampled, or stale, or partially synthetic | Funnels over large date ranges, slow flows |
| ⚪ **Gray** | Preview only — synthetic or no upstream source | Brand-new registered metrics in the 7-day warm-up window |

**Apply to every chart footer.** PMs need to know at a glance whether to bet a campaign on this number.

### Drift, freshness, null-rate — surface them quietly

- **Drift** (data distribution changed vs last week): shown as an amber badge on the metric tile, click to see the drift event chart
- **Freshness SLA** (% of refresh windows met): shown as a percentage on the metric card hover
- **Null rate** (% of users with no value): only shown if >5%

PMs should NOT see these as primary navigation. They're hover/click-through trust signals.

## A.9 Anti-patterns (don't do these)

| Anti-pattern | Why it kills | What to do instead |
|---|---|---|
| **Empty exploration canvas** ("Choose a chart type → blank screen") | Cold-start paralysis | Land on a curated "Hermes noticed"-style inbox of anomalies; or templates ("Start with: funnel / cohort / retention") |
| **SQL escape hatches surfaced in PM UI** | PMs paste in nonsense; analysts get pinged; trust erodes | Hide SQL behind a "Show me how this query runs" disclosure; never let PMs edit it directly in v1 |
| **One giant filter sidebar for everything** | Becomes a 40-row filter screen with no hierarchy | Filters live INLINE in builders (per-step in funnels, per-clause in cohorts). Saved cohorts replace global filters for cross-cutting reuse |
| **Showing every possible event/property** | Lexicon with 600 events is unusable | Default to "frequently used" + "recently added"; full taxonomy under a "see all" disclosure |
| **Inconsistent grain naming** ("DAU" on one screen, "active users daily" on another) | Erodes trust | Single dictionary owned by data team; display names render everywhere identically |
| **Formula builder with no preview** | PMs write `(A-B)/B` and don't realize they got a NaN | Live preview is non-negotiable |
| **Confusing exploration metric with registered metric** | "I saved it last week, where did it go?" "Oh, that was just local to the report." | Two clearly distinct states: **exploration** (scratchpad) and **registered metric** (the Feature Store). Every save action asks which one |
| **Mid-flow modals to confirm trivial actions** | "Are you sure you want to change the conversion window?" | Just change it. Re-run the query. Show the new result |

---

# Part B — UX Brief & Wireframes

> **Convention used in this section:** All wireframes are ASCII. `▼` = dropdown picker. `[ Button ]` = clickable. `🟢🟠⚪` = provenance dots. `─` = horizontal rule. Aim for screens to fit on a 13" laptop without horizontal scroll.

## B.1 Information architecture

```
┌─ Top-level nav ─────────────────────────────────────────────────────┐
│                                                                      │
│   Home    Explore    Metrics                       [⚙]  [user ▾]     │
│           ──────                                                     │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

  Home          → landing inbox of anomalies + saved explorations
  Explore       → the 5 builders (Events / Funnels / Cohorts / Retention / Flows)
  Metrics       → the registered metric library (Feature Store, PM-facing)
                  + Metric Detail pages
```

Two-level IA. No deeper. Anything else hides behind an in-page tab or a side rail.

## B.2 Landing / Home

Lands here on session start.

```
┌─ Home ──────────────────────────────────────────────────────────────────┐
│                                                                          │
│   What's changed                                                         │
│   ─────────────                                                          │
│   ┌────────────────────────────────────────────────────────────────┐    │
│   │ 🟠  CFM ARPDAU down 7% vs last 4 weeks                         │    │
│   │     Driven by lower spend per paying user, not fewer payers.   │    │
│   │     [ Investigate → ]                                           │    │
│   └────────────────────────────────────────────────────────────────┘    │
│   ┌────────────────────────────────────────────────────────────────┐    │
│   │ 🟢  3 new whales in PT registered yesterday                    │    │
│   │     [ See cohort → ]                                            │    │
│   └────────────────────────────────────────────────────────────────┘    │
│   ┌────────────────────────────────────────────────────────────────┐    │
│   │ 🟠  Tutorial-completion funnel dropped to 41% (was 58%)        │    │
│   │     [ Open funnel → ]                                           │    │
│   └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│   Or start fresh                                                         │
│   ──────────────                                                         │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│   │  📋          │  │  ⇉          │  │  👥         │  │  📈         │    │
│   │              │  │              │  │             │  │             │    │
│   │  Browse      │  │  Build a     │  │ Define a    │  │ Retention   │    │
│   │  events      │  │  funnel      │  │ cohort      │  │ curve       │    │
│   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
│   ┌─────────────┐  ┌─────────────┐                                       │
│   │  ⤳          │  │  Σ           │                                      │
│   │              │  │              │                                      │
│   │  Trace user  │  │  Build a     │                                      │
│   │  flows       │  │  metric      │                                      │
│   └─────────────┘  └─────────────┘                                       │
│                                                                          │
│   Recent saved explorations                                              │
│   ─────────────────────────                                              │
│   • Whale recovery cohort (you · 2h ago)        [ Open → ] [ ⋯ ]        │
│   • Tutorial funnel · CFM v2 (you · yesterday)  [ Open → ] [ ⋯ ]        │
│   • [ See all 12 → ]                                                     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- The "What's changed" cards are computed by anomaly detection on registered metrics (Phase 1 = simple thresholding; Phase 2 = real models).
- "Or start fresh" is the cold-start backstop. Big icons, big targets, no jargon.
- "Trace user flows" is the Sankey/Flow primitive. Renamed to feel less technical.

## B.3 Event Explorer (data dictionary)

Reached via "Browse events" tile.

```
┌─ Explore → Events ──────────────────────────────────────────────────────┐
│                                                                          │
│  Game: [ CFM ▼ ]    Time range: [ Last 7d ▼ ]    Source: [ All ▼ ]      │
│                                                                          │
│  Search events  [ purchase____________________ 🔍 ]                      │
│                                                                          │
│ ┌─────────────────────────────────────────┬─────────────────────────────┐│
│ │ Events (32 in CFM)                      │ Selected: purchase_completed││
│ │ ─────────────────────────                │ ─────────────────────────── ││
│ │                                          │                              ││
│ │ 🟢 app_open                              │ 🟢 Real · raw events         ││
│ │    1.2M / day · 32 reports               │ Trino · cfm_vn.events        ││
│ │                                          │                              ││
│ │ 🟢 session_start                         │ Description                  ││
│ │    1.1M / day · 28 reports               │ Fires when a user completes  ││
│ │                                          │ a purchase. Includes IAP     ││
│ │ 🟢 level_complete                        │ and battle-pass.             ││
│ │    412k / day · 19 reports               │ [✎ Edit]                     ││
│ │                                          │                              ││
│ │ 🟢 purchase_completed   ◀ selected       │ Properties (8)               ││
│ │    18k / day · 14 reports                │ ─────────────                ││
│ │                                          │ # amount_local       50000   ││
│ │ 🟠 ad_impression                         │ A currency           VND     ││
│ │    sampled · 240k / day · 6 reports      │ # amount_usd         2.05    ││
│ │                                          │ A sku                "p_010"  ││
│ │ ⚪ tutorial_step_skipped                 │ A purchase_type      IAP     ││
│ │    preview only · 12 / day · 0 reports   │ # user_level         42      ││
│ │                                          │ 📅 first_purchase_at  ...    ││
│ │ [ See all 32 → ]                         │ ✓ is_first_purchase  TRUE    ││
│ │                                          │                              ││
│ │                                          │ [ Sample 8 events → ]        ││
│ │                                          │                              ││
│ │                                          │ Used in                      ││
│ │                                          │ ─────────                    ││
│ │                                          │ • Whale funnel               ││
│ │                                          │ • ARPDAU metric              ││
│ │                                          │ • Tet event cohort           ││
│ │                                          │                              ││
│ │                                          │ ┌──────────────────────────┐ ││
│ │                                          │ │ Use this event in:       │ ││
│ │                                          │ │ [ Funnel ] [ Cohort ]    │ ││
│ │                                          │ │ [ Flow ]   [ Metric ]    │ ││
│ │                                          │ └──────────────────────────┘ ││
│ └─────────────────────────────────────────┴─────────────────────────────┘│
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- Left rail is the event list sorted by usage (most-used first).
- Property types use single-character icons: `#` number, `A` string, `✓` boolean, `📅` datetime.
- "Sample 8 events" expands an inline panel of 8 anonymized real event rows — the trust accelerator.
- "Used in" lists downstream artifacts (existing metrics, segments). Click any to navigate.
- Bottom-right action card is the bridge: from event browsing into builder primitives. The event is pre-filled when the PM lands.

## B.4 Funnel Builder

```
┌─ Explore → Funnel ──────────────────────────────────────────────────────┐
│                                                                          │
│  ◀ Back   Untitled funnel · CFM       [ Save ] [ Save as metric ]  [⋯]  │
│                                                                          │
│  Game [ CFM ▼ ]   Time [ Last 30d ▼ ]   Window [ 14d ▼ ]                │
│  Cohort filter [ + Add cohort ]                                          │
│  Show as [ Step-over-step ▼ ]   Compare [ + Add comparison ]            │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                                                                       ││
│  │  Step 1   [ app_open ▼ ]                                              ││
│  │           [ + property filter ]                                       ││
│  │                                            128,402 users  ────── 100% ││
│  │                                                                       ││
│  │           ↓ within 14d                                                ││
│  │                                                                       ││
│  │  Step 2   [ tutorial_complete ▼ ]                                     ││
│  │           [ + property filter ]                                       ││
│  │                                             52,615 users  ────  41.0% ││
│  │                                                            ▼ 75,787 lost││
│  │                                                                       ││
│  │           ↓ within 14d                                                ││
│  │                                                                       ││
│  │  Step 3   [ purchase_completed ▼ ]                                    ││
│  │           [ amount_local ≥ 50000 × ]                                  ││
│  │                                              4,108 users  ─    7.8%  ││
│  │                                                            ▼ 48,507 lost││
│  │                                                                       ││
│  │  [ + Add step ]                                                       ││
│  │                                                                       ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  Overall conversion: app_open → purchase ≥50k VND  =  3.2%  (4,108 users)│
│  🟠 Raw events · cfm_vn.events · 312M rows scanned · 6.2s                │
│                                                                          │
│  ┌─ Chart ────────────────────────────────────────────────────────────┐ │
│  │                                                                     │ │
│  │  █████████████████████████████████████  app_open          128,402   │ │
│  │  █████████████████                      tutorial_complete  52,615   │ │
│  │  █                                      purchase_completed  4,108   │ │
│  │                                                                     │ │
│  │  ⓘ Bar length = absolute users, % = conversion vs prior step       │ │
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- Each step has its own inline property filter chip strip. No global filter panel for funnel-internal filters.
- The "▼ 75,787 lost" red drop-off callout is the action signal — clicking it opens "Where did the lost users go?" (links to Flow analysis pre-filtered).
- Toggle between "Step-over-step" and "Overall" conversion at the top.
- "Compare" lets you overlay two cohorts (e.g., new users vs returning users) — dashed second line on the chart.
- "Save as metric" is the explicit bridge to the Formula Builder pre-filled with `conversion_rate = step_N_users / step_1_users`.

## B.5 Cohort Builder

```
┌─ Explore → Cohort ──────────────────────────────────────────────────────┐
│                                                                          │
│  ◀ Back   Untitled cohort · CFM   [ Save cohort ] [ Save as metric ]    │
│                                                                          │
│  Game [ CFM ▼ ]   Time anchor [ Last 30d ▼ ]                            │
│                                                                          │
│  Users WHO                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  Group A    AND       Group B    AND       Group C   [ + Group ]   ││
│  │                                                                       ││
│  │  did                          did                          property   ││
│  │  [ purchase_completed ▼ ]      [ session_start ▼ ]          spend_   ││
│  │  [ ≥ 1 time ▼ ]               [ ≥ 5 times ▼ ]               tier =   ││
│  │  in [ last 30d ▼ ]             in [ last 7d ▼ ]              [ whale ▼]││
│  │  [ amount_local ≥ 100000 × ]   [ +filter ]                            ││
│  │  [ +filter ]                                                          ││
│  │                                                                       ││
│  │  OR                            OR                                     ││
│  │  did                                                                  ││
│  │  [ battle_pass_buy ▼ ]                                                ││
│  │  [ ≥ 1 time ▼ ]                                                       ││
│  │  in [ last 30d ▼ ]                                                    ││
│  │                                                                       ││
│  │  [ + OR clause ]               [ + OR clause ]                        ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  Exclude                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │  did NOT do [ refund_request ▼ ]  in [ last 90d ▼ ]                  ││
│  │  [ + Exclusion ]                                                      ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    │
│  Audience size: 33,813 users         🟢 Daily aggregate · user_360       │
│                  ────────                last refresh 14:02 · 153ms      │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━    │
│                                                                          │
│  ┌─ Composition preview ──────────────────────────────────────────────┐ │
│  │                                                                     │ │
│  │  By spend tier:    whale ████████████  18,205                      │ │
│  │                    mid   ██████        12,108                       │ │
│  │                    low   ██              3,500                       │ │
│  │                                                                     │ │
│  │  By region:        VN    ████████████  25,602                       │ │
│  │                    TH    ██               5,302                      │ │
│  │                    Other █                2,909                      │ │
│  │                                                                     │ │
│  │  By lifecycle:     veteran ██████      18,008                       │ │
│  │                    mid     ████████    10,205                       │ │
│  │                    nru     ██           5,600                       │ │
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  [ Use this cohort in a funnel → ]  [ ... in retention → ]              │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- AND glues Group A / B / C (each is an OR-group of clauses). No nested ANDs inside groups — fights the visual model.
- Live audience count updates on every change with the spinner inline.
- Composition preview is borrowed from Hermes' coverage segmentation — 2–3 horizontal bar charts breaking the cohort down by canonical user properties. Crucial for the PM to sanity-check "did I just describe whales? yes I did."
- Outbound CTAs at the bottom — cohort as a filter on a funnel/retention is the most common next step.

## B.6 Retention Chart

```
┌─ Explore → Retention ───────────────────────────────────────────────────┐
│                                                                          │
│  ◀ Back   Untitled retention · CFM    [ Save ] [ Save as metric ]       │
│                                                                          │
│  Game [ CFM ▼ ]                                                          │
│  Cohort   [ All users ▼ ]   ← pick a saved Cohort                       │
│  Returning event  [ app_open ▼ ]                                         │
│  Anchor event     [ first_seen ▼ ]                                       │
│  Time grain       [ Day ▼ ]                                              │
│  Retention type   [ Day-N (bracket) ▼ ]                                 │
│  Date range       [ Last 8 weeks ▼ ]                                    │
│                                                                          │
│  ┌─ Heatmap ──────────────────────────────────────────────────────────┐ │
│  │                                                                     │ │
│  │  Cohort          D0    D1    D3    D7    D14   D30   D60   D90    │ │
│  │  ──────          ───   ───   ───   ───   ───   ───   ───   ───    │ │
│  │  Week of Mar 02  100%  ▓62   ▓41   ▓28   ░18   ░12    -     -     │ │
│  │  Week of Mar 09  100%  ▓60   ▓39   ▓26   ░16   ░10    -     -     │ │
│  │  Week of Mar 16  100%  ▓58   ▓37   ▓24   ░15    -     -     -     │ │
│  │  Week of Mar 23  100%  ▓55   ▓35   ░22    -     -     -     -     │ │
│  │  Week of Mar 30  100%  ▓52   ▓32    -     -     -     -     -     │ │
│  │  Week of Apr 06  100%  ▓50    -     -     -     -     -     -     │ │
│  │                                                                     │ │
│  │  ▓ = darker color = higher retention                                │ │
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  ┌─ Curve ────────────────────────────────────────────────────────────┐ │
│  │   100│●                                                             │ │
│  │      │ ●                                                            │ │
│  │    60│  ● ─ ─ Week Mar 02                                           │ │
│  │      │   ●                                                          │ │
│  │    40│    ● ─ ─ ─                                                   │ │
│  │      │      ●                                                       │ │
│  │    20│        ● ─ ─ ─ ─ ─ ─                                         │ │
│  │      └─────────────────────────────                                  │ │
│  │        D0  D1  D3  D7  D14  D30                                     │ │
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  🟢 Daily aggregate · active_daily · 200ms                              │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- Heatmap rows sorted newest-cohort first.
- Diagonals being empty for recent cohorts is correct (D90 doesn't exist yet for the latest week). Use `-`, not 0%, to communicate "not enough time elapsed."
- Below-heatmap curve view doubles up to show trend (are newer cohorts retaining worse?). One screen.
- "Returning event" defaults to `app_open` but the PM can pick any event — that's the "did they come back AND do X" question.

## B.7 Flow / Path Analysis

```
┌─ Explore → Flow ────────────────────────────────────────────────────────┐
│                                                                          │
│  ◀ Back   Untitled flow · CFM         [ Save ] [ ⋯ ]                    │
│                                                                          │
│  Direction [ AFTER ▼ ]   Anchor event [ tutorial_start ▼ ]               │
│  Steps     [ 4 ▼ ]   Session window [ 30 min ▼ ]                        │
│  Cohort filter [ + Add cohort ]                                          │
│                                                                          │
│  ┌─ Sankey ───────────────────────────────────────────────────────────┐ │
│  │                                                                     │ │
│  │   tutorial_start ─────█████ tutorial_step_1 ─█████ tutorial_complete│ │
│  │   (128k)              ████  (105k · 82%)    ████  (72k · 68%)      │ │
│  │                       ─███                  ─███                    │ │
│  │                       ──█ session_end       ──█ session_end         │ │
│  │                       (18k · 14%)            (23k · 22%)             │ │
│  │                                                                     │ │
│  │                       ──█ app_background    ──█ purchase_open       │ │
│  │                       (5k · 4%)              (10k · 9%)              │ │
│  │                                                                     │ │
│  │   ─────────────────────────────────────────────────────────────    │ │
│  │   Step:    anchor       +1                  +2                      │ │
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  Hovered: "tutorial_start → session_end" — 18,203 users (14%)            │
│  [ Save this path as a cohort → ]  [ Investigate as funnel → ]          │
│                                                                          │
│  🟠 Raw events · cfm_vn.events · 312M scanned · 11.2s                   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- Sankey is the only chart. Don't try a tree or table view.
- Direction toggle (AFTER / BEFORE) at the top — both modes commonly asked for.
- Hovering a path band shows raw + % at the bottom; click to investigate as a funnel.
- "Save this path as a cohort" turns a specific Sankey path into a behavioral cohort (users who took this exact sequence) — the bridge to Cohort Builder.

## B.8 Formula Builder (no-code metric authoring)

The most novel surface. Combines Mixpanel Custom Property + Formula into one tool.

```
┌─ Explore → New Metric ──────────────────────────────────────────────────┐
│                                                                          │
│  ◀ Back   New metric                  [ Discard ]   [ Register → ]      │
│                                                                          │
│  Name:        [ Whale 7-day Recharge Rate __________________________ ]   │
│  ID (auto):   whale_recharge_rate_7d                                     │
│                                                                          │
│  Mode:  ( ● ) Metric (number per query)                                  │
│         (   ) Property (per-event/per-user)                              │
│                                                                          │
│  ────────────────────────────────────────────────────────────────────    │
│  Inputs                                                                  │
│  ────────                                                                │
│                                                                          │
│  A  [ whale_users (cohort) ▼ ]   count of users           18,205         │
│     filter: spend_tier_lifetime = whale                                  │
│                                                                          │
│  B  [ whale_users (cohort) ▼ ]   count of users           ←─────── same  │
│     filter: WHO did recharge in last 7d                                  │
│                                                                  4,621   │
│                                                                          │
│  [ + Add input ]                                                         │
│                                                                          │
│  ────────────────────────────────────────────────────────────────────    │
│  Formula                                                                 │
│  ───────                                                                 │
│                                                                          │
│  [ B / A ____________________________________________________________ ]  │
│                                                                          │
│  Quick insert:  [ + ] [ − ] [ × ] [ ÷ ] [ % ] [ Δ ]                     │
│  Templates:     [ Rate ▼ ] [ Growth ▼ ] [ Avg ▼ ] [ Ratio ▼ ]           │
│                                                                          │
│  ─ ⓘ Type detected: ratio (0..1) ────────────────────────────────────    │
│                                                                          │
│  Preview                                                                 │
│  ───────                                                                 │
│  Result:  0.254  (25.4%)        🟢 Daily aggregate · 312ms               │
│                                                                          │
│  ┌─ Over time ────────────────────────────────────────────────────────┐ │
│  │ 30% ┐                                                              │ │
│  │     │     ●                                                        │ │
│  │ 25% │  ●     ●  ●                                                  │ │
│  │     │           ●  ●                                               │ │
│  │ 20% │              ●  ●  ●                                         │ │
│  │     └─────────────────────────                                     │ │
│  │      Apr 1     Apr 15     Apr 29                                   │ │
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  Description (≤280 chars)                                                │
│  ─────────────────────────                                               │
│  [ Among CFM users with whale lifetime spend tier, the percentage who   ]│
│  [ recharged in the last 7 days. Used for targeting at-risk whales.____ ]│
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- Two-mode toggle at top. **Metric** mode (default) = aggregate result over a query. **Property** mode = per-row derivation.
- Inputs section: each input gets a letter (A, B, ...). Input source can be: a measure, a cohort size, an existing metric, a property aggregation.
- Formula text box accepts simple expressions. **Quick-insert chips** for non-text users — click `÷` to insert at cursor.
- **Templates** pre-fill known shapes — "Rate" pre-fills `B/A`, "Growth" pre-fills `(B-A)/A`, etc. Removes the formula-blank-page problem.
- Type-detection auto-classifies output as `count`, `ratio (0..1)`, `currency`, `duration`, `delta`. Used to set sensible defaults in chart axes + downstream Hermes Feature Store schema.
- Live preview + spark chart. **Without this, the builder fails.**
- Description is gated short — Hermes Feature Store enforces 280 chars; mirror here.
- The "Register" button transitions to B.9.

## B.9 Save & Register a Metric (handoff modal)

```
┌─ Register metric · whale_recharge_rate_7d ──────────────────────────────┐
│                                                                          │
│  About to register a new metric                                          │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  Name        Whale 7-day Recharge Rate                              │  │
│  │  ID          whale_recharge_rate_7d                                 │  │
│  │  Type        Ratio (0..1)                                            │  │
│  │  Description Among CFM users with whale lifetime spend tier, the    │  │
│  │              percentage who recharged in the last 7 days. Used for  │  │
│  │              targeting at-risk whales.                              │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  Classification                                                          │
│  ──────────────                                                          │
│  Domain        [ Monetization ▼ ]                                        │
│  Games         [✓ CFM]  [ ] PT  [ ] NTH  [ ] TF  [ ] COS  [ ] PTG       │
│  Latency       (●) Batch warm (1h)                                      │
│                ( ) Batch cold (1d)                                       │
│                ( ) Realtime (<1s)  ⓘ requires raw-event source           │
│  Use case      [ Targeting churn-risk whales for the rescue campaign ]   │
│                                                                          │
│  Underlying definition (read-only)                                       │
│  ─────────────────────────────────                                       │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  -- generated from your formula                                     │  │
│  │  WITH whale_users AS (                                              │  │
│  │    SELECT user_id FROM user_360                                     │  │
│  │    WHERE game = 'cfm' AND spend_tier_lifetime = 'whale'             │  │
│  │  ),                                                                  │  │
│  │  whale_recharged AS (                                                │  │
│  │    SELECT DISTINCT user_id FROM user_recharge_daily                  │  │
│  │    WHERE user_id IN (SELECT user_id FROM whale_users)                │  │
│  │    AND recharge_date >= CURRENT_DATE - INTERVAL '7 day'              │  │
│  │  )                                                                   │  │
│  │  SELECT (SELECT COUNT(*) FROM whale_recharged) * 1.0                 │  │
│  │       / (SELECT COUNT(*) FROM whale_users) AS value                  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│  [ Copy SQL ]   ⓘ Engineering will own and may rewrite this              │
│                                                                          │
│  What happens next                                                       │
│  ────────────────                                                        │
│   1.  Status: requested  →  in_review (data eng. picks it up)            │
│   2.  Engineering reviews SQL, decides on cube/dbt placement             │
│   3.  First backfill runs (~7-day warm-up)                               │
│   4.  Metric appears in your library with health/drift signals           │
│   5.  You'll be notified when it's live                                  │
│                                                                          │
│  ETA: 2 business days for review + first backfill                        │
│                                                                          │
│  [ Cancel ]                              [ Save draft ]  [ Register → ]  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- Single modal, no wizard. The PM has already done the hard work in the Formula Builder.
- "Latency" mirrors Hermes' Realtime / Batch warm / Batch cold contract. Disabled options grayed with a tooltip explaining why (e.g., realtime needs raw-event source not present yet).
- Use-case field is **mandatory** — prevents queue spam. If PM can't articulate why they want this metric, they probably don't want it.
- Generated SQL preview is read-only but copy-able. This is the engineer-audit lane Hermes' Feature Detail Engineer tab eventually displays.
- "Save draft" path lets PM save without queueing — useful for iterative work.

## B.10 Metric Library (post-registration browse)

This is the PM-facing Feature Store. **Game-anchored UX, generic principles.**

```
┌─ Metrics ───────────────────────────────────────────────────────────────┐
│                                                                          │
│  76 metrics    [ + Register new ]              Q [ search ____________ ] │
│                                                                          │
│  Stat strip                                                              │
│  ┌────────┬─────────┬──────────┬─────────────┬───────────────┬────────┐ │
│  │ Total  │Platform │ Realtime │ Batch warm  │ Batch cold    │ Drift  │ │
│  │  76    │   3     │   12     │     42      │     22        │   5 🟠 │ │
│  └────────┴─────────┴──────────┴─────────────┴───────────────┴────────┘ │
│                                                                          │
│  Quick filters                                                           │
│  [ Browse by domain ]  [ + Register ]  [ Recently added ]  [ Drift 5 ]  │
│                                                                          │
│ ┌─ Filters ──────┬─ List ──────────────────────────────────────────────┐│
│ │                │                                                       ││
│ │ Type           │ Group by [ Domain ▼ ]   Sort [ Most used ▼ ]         ││
│ │ [✓] Number     │                                                       ││
│ │ [✓] Ratio      │ ▾ Monetization (18)                                  ││
│ │ [ ] Currency   │                                                       ││
│ │                │  ┌────────────────────────────────────────────────┐  ││
│ │ Latency        │  │ 🟢 lifetime_revenue_local      ── currency      │  ││
│ │ [ ] Realtime   │  │    Total revenue per user over their lifetime   │  ││
│ │ [✓] Batch warm │  │    [CFM] [PT] · Batch cold · 4 reports          │  ││
│ │ [✓] Batch cold │  │    7-day sparkline ────────              98%fresh│  ││
│ │                │  └────────────────────────────────────────────────┘  ││
│ │ Games          │                                                       ││
│ │ [✓] CFM        │  ┌────────────────────────────────────────────────┐  ││
│ │ [ ] PT         │  │ 🟢 whale_recharge_rate_7d   ●NEW● ─ ratio       │  ││
│ │ [ ] NTH        │  │    Among whales, % who recharged in 7d           │  ││
│ │ [ ] TF         │  │    [CFM] · Batch warm · 0 reports                │  ││
│ │ [ ] COS        │  │    [warming up · 4 days remaining]               │  ││
│ │                │  └────────────────────────────────────────────────┘  ││
│ │ Platform       │                                                       ││
│ │ [ ] Platform   │  ┌────────────────────────────────────────────────┐  ││
│ │     only       │  │ 🟠 arpdau_local                ── currency      │  ││
│ │                │  │    Average revenue per daily active user        │  ││
│ │ Status         │  │    [CFM] · Batch warm · 22 reports               │  ││
│ │ [✓] Active     │  │    Drift detected ⚠ · 7-day sparkline ──────    │  ││
│ │ [ ] Requested  │  └────────────────────────────────────────────────┘  ││
│ │                │                                                       ││
│ │                │ ▸ Engagement (24)                                    ││
│ │                │ ▸ Acquisition (12)                                   ││
│ │                │ ▸ Retention (14)                                     ││
│ │                │ ▸ Quality of life (8)                                ││
│ └────────────────┴───────────────────────────────────────────────────────┘│
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- Stat strip + filter rail + group-by + sort: mirrors Hermes Feature Store v2 library layout.
- Status `Requested` is a NEW state — metrics the PM has filed but engineering hasn't built yet. They're listed but disabled (gray, no usage stats).
- Each row card shows provenance dot + name + type + description + games chip cluster + latency + usage + sparkline + freshness%.
- "Browse by domain" is the primary entry-point — replicates Hermes pattern.

## B.11 Metric Detail (post-registration deep dive)

Three persona tabs per Hermes. **LiveOps tab ships in v1**, Analyst + Engineer tabs ship in later iterations.

```
┌─ Metrics → whale_recharge_rate_7d ──────────────────────────────────────┐
│                                                                          │
│  ◀ Back to library                                                       │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Whale 7-day Recharge Rate            Ratio · Batch warm · [CFM] │    │
│  │ whale_recharge_rate_7d                                          │    │
│  │ Among CFM users with whale lifetime spend tier, the percentage  │    │
│  │ who recharged in the last 7 days. Used for targeting at-risk    │    │
│  │ whales.                                                          │    │
│  │                                       [ Use in segment ] [ ⋯ ]  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  Tabs:  ● LiveOps   ○ Analyst   ○ Engineer                              │
│                                                                          │
│  ┌─ Source provenance ──────────────────────────────────────────────┐   │
│  │ 🟢  Real  ·  Trino-derived                                        │   │
│  │     Computed from cfm_vn events + user_360 cube.                  │   │
│  │     Safe to bet a campaign on this.                               │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─ Health verdict ─────────────────────────────────────────────────┐   │
│  │ 🟢  Healthy                                                       │   │
│  │     Drift 0.08 (low)  ·  Freshness 99%  ·  Null 0%  ·  Coverage  │   │
│  │     98% of WhaleUsers                                              │   │
│  │     [ ▾ See signals ]                                              │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─ Threshold playground ──────────────────────────────────────────┐    │
│  │                                                                   │    │
│  │ Audience where whale_recharge_rate_7d  [ ≥ ▼ ]  [────●──────] 0.3 │    │
│  │                                                                   │    │
│  │                                            ── 8,402 users  ──    │    │
│  │                                                                   │    │
│  │  Histogram of metric values across CFM whales (n=18,205):         │    │
│  │  0.0 ▓▓                                                           │    │
│  │  0.1 ▓▓▓▓▓                                                        │    │
│  │  0.2 ▓▓▓▓▓▓▓                                                      │    │
│  │  0.3 ▓▓▓▓▓▓▓▓▓ ◀ threshold here                                   │    │
│  │  0.4 ▓▓▓▓▓                                                        │    │
│  │  0.5 ▓▓                                                            │    │
│  │  0.6 ▓                                                            │    │
│  │                                                                   │    │
│  │  [ Use in segment → ]                                             │    │
│  └───────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  Related metrics                                                         │
│  ─────────────────                                                       │
│  • lifetime_revenue_local · 0.71 correlation                            │
│  • days_since_last_recharge · -0.58 correlation                          │
│  • whale_session_count_7d · 0.34 correlation                             │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Notes:**
- Three-tab persona pattern straight from Hermes Feature Store. **LiveOps is default**, the only tab v1 needs fully fleshed.
- The threshold playground is generalized from Hermes' ThresholdPlaygroundPanel — let the PM prototype an audience without re-running the cohort builder.
- "Use in segment" CTA is the bridge to whatever segment composer lives downstream (Hermes Segments module or new equivalent).

## B.12 Copy guidelines (microcopy & vocabulary)

| Where | Use | Don't use |
|---|---|---|
| PM-facing nav | "Metrics" | "Features" |
| PM-facing detail | "Metric" | "Feature" |
| Engineer-facing handoff | "Feature ID" | "Metric ID" |
| Provenance dot tooltip | "Real · raw events · last refresh 14:02" | "🟢" alone (no text) |
| Funnel drop-off | "12,481 users lost (23.2%)" — absolute first | "23.2% conversion" alone |
| Cohort builder | "Users WHO did X with property Y" | "Set theory of event predicates" |
| Latency | "Realtime · Batch warm · Batch cold" | "Tier A / Tier B" (engineer-speak) |
| Empty state | "No metrics in this domain yet — register one →" | "No results found." |
| Loading > 3s | "Crunching 312M events… ~6s" — show progress, set expectations | spinner alone |
| Failed query | "Query failed — your filter on `amount_usd` returned no matching events. [Edit filter]" | "Error 500" |
| Newly registered | "Warming up · 4 days until first health signals" | "No data" |

## B.13 Empty / loading / error states

**Empty state (any builder with no inputs):**
```
┌─────────────────────────────────────────┐
│                                          │
│         ⇉                                │
│                                          │
│    Pick an event to start.               │
│    Try one of these:                     │
│                                          │
│    [ app_open ]  [ purchase_completed ]  │
│    [ session_start ]  [ tutorial_start ] │
│                                          │
│    Or [ Browse events → ]                │
│                                          │
└─────────────────────────────────────────┘
```

**Loading (raw event grain > 3s):**
```
┌─────────────────────────────────────────┐
│  Crunching 312M events…  ~6 seconds      │
│  ▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░  estimated         │
│                                          │
│  ⓘ Funnels over raw events take longer.  │
│    Switch to "Daily aggregate" if you    │
│    only need totals.                     │
└─────────────────────────────────────────┘
```

**Error (over-filtered, zero results):**
```
┌─────────────────────────────────────────┐
│  ⚠  No users match this combination      │
│                                          │
│  Your filters resulted in 0 users.       │
│  Most likely cause:                      │
│  • amount_local ≥ 100,000 VND on Step 3  │
│    excludes 96% of purchases.            │
│                                          │
│  [ Relax filter ]  [ Edit funnel ]       │
└─────────────────────────────────────────┘
```

**Newly-registered metric (warm-up state):**
```
┌─────────────────────────────────────────┐
│  whale_recharge_rate_7d                  │
│  ⚪ Warming up                            │
│                                          │
│  This metric was registered 3 days ago.  │
│  Health signals, drift detection, and    │
│  cohort breakdowns appear after 7 days   │
│  of backfill.                            │
│                                          │
│  In the meantime, you can:               │
│  [ See SQL ]  [ Watch progress ]         │
└─────────────────────────────────────────┘
```

## B.14 Build sequencing & cut lines

> Order matters more than scope. Ship in this order; each tier is a usable product.

| Tier | Surface | Why this tier |
|---|---|---|
| **T1 — MVP, ship first** | Event Explorer · Cohort Builder · Save (no registration) | Browsing events + slicing users is the most-used analyst workflow. Save = scratchpad (local, not Feature Store). Daily-aggregate grain only — no raw-event infra yet |
| **T2 — Bridge to registration** | Save modal → Feature Store registration · Metric Library (read-only) · Metric Detail LiveOps tab | This is where the PM gets persistent value. Engineering queue + SQL handoff = closes the loop |
| **T3 — Authoring** | Formula Builder · Funnel Builder · Retention chart | Now PMs can *create* numbers, not just slice. Funnel + Retention can ship before raw-event grain by faking funnels as cohort-sequences (1-step approximation) |
| **T4 — Raw-event grain** | Cube/dbt model over Trino events · enables real multi-step Funnels and Flows | Heaviest infra lift. Defer until T1–T3 validated |
| **T5 — Flow / Path** | Sankey Flow Builder | Lowest-frequency primitive in PM workflow surveys. Defer |
| **T6 — Out of scope for this work** | Anomaly inbox on Home · AI/agent · cross-game roll-ups | Phase 2 territory |

**Cut-lines (descope without losing the product):**
- Formula Builder can ship with **Templates only** in v1 (no free-text formula box). PMs pick Rate / Growth / Ratio / Average; can't write custom formulas. Phases later.
- Metric Detail Analyst + Engineer tabs ship empty in v1 ("Coming soon"). Only LiveOps tab needs to work.
- Composition preview in Cohort Builder can ship with **one breakdown** (spend tier) instead of three. Cheap win.
- Provenance amber/gray dots can ship as a single status badge ("Real · 200ms") in v1 — full three-tier signal in v2.

---

# Part C — Risks & Open Questions

## C.1 Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Raw-event grain queries (T4) too slow for PM patience (>15s) | High | Cube pre-aggregations + Cube Store materialization; cap default time-range to 7 days; surface latency estimate before execution |
| PMs file low-quality metric requests, eng queue clogs | Medium | Mandatory `use_case` field; auto-link to existing similar metrics ("we already have arpdau_local — is that what you want?"); rate-limit per PM per week |
| Confusion between "saved exploration" (scratchpad) and "registered metric" | Medium | Two distinct save buttons + two distinct browse surfaces; never mix |
| Formula Builder produces SQL that doesn't compile (e.g., type mismatch) | Medium | Engineer review step before activation; PM gets feedback as a comment, not silent failure |
| Cube cube/view drift from Hermes Feature Store registry | High | Single source of truth — Hermes catalog-api holds metric metadata; Cube YAML is generated FROM the catalog, not the other way |
| Game-specific examples in UI lock out non-CFM teams | Medium | Game selector in nav; CFM is default but every screen accepts `game=*` for cross-game queries |

## C.2 Open questions

1. **Where does this explorer live in code?** Same repo as Cube (`cube-dev`) → new web app? Or extend Hermes? Affects ownership, deploy story, design system reuse.
2. **Engineering queue persistence — where?** Hermes already has Postgres + catalog-api. New table there, or new service?
3. **Who writes the dbt SQL when engineering picks up a request?** Manual (data engineer) v1, with PM-side automation later? Or auto-generated from Formula Builder and human-reviewed?
4. **Daily-aggregate cubes (active_daily, recharge, mf_users, user_recharge_daily) cover monetization + engagement well — do they cover acquisition & quality?** May need new cubes before the explorer can answer common acquisition questions.
5. **Is there a raw-event cube/view ready in Cube, or does T4 require dbt + Cube modeling work?** Spec says no — confirm before sizing T4.
6. **Game taxonomy:** is CFM `cfm_vn` the only data source today, or are PTG / NTH / TF / COS / PT also queryable?
7. **Saved-exploration ownership model:** can two PMs see each other's saved cohorts/funnels? Org-shared or personal? Phase-1 KISS answer is "personal only", but worth confirming.
8. **Formula Builder + cohort composition:** can a cohort itself be an input to a formula? (E.g., `len(cohort_A) / len(cohort_B)`). Recommend yes — covers 80% of "rate" metrics — but adds cohort dependency tracking to the engineering queue.

---

## Sources

### External research (web)
- [Mixpanel Custom Properties Docs](https://docs.mixpanel.com/docs/features/custom-properties)
- [Mixpanel Formulas (saved metrics)](https://docs.mixpanel.com/changelogs/2023-11-09-saved-formulas)
- [Mixpanel Lexicon (data dictionary)](https://docs.mixpanel.com/docs/data-governance/lexicon)
- [Mixpanel Flows (Sankey paths)](https://docs.mixpanel.com/docs/reports/flows)
- [Mixpanel Retention chart](https://docs.mixpanel.com/docs/reports/retention)
- [Amplitude Behavioral Cohorts](https://amplitude.com/docs/analytics/behavioral-cohorts)
- [Amplitude Define a Cohort](https://amplitude.com/docs/analytics/define-cohort)
- [Amplitude Funnel Analysis chart](https://help.amplitude.com/hc/en-us/articles/115001351507-Get-the-most-out-of-Amplitude-s-Funnel-Analysis-chart)
- [Amplitude Pathfinder (Sankey paths)](https://e-cens.com/blog/amplitude-101-advanced-analysis-with-pathfinder-cohorts/)
- [Amplitude Event Taxonomy framework](https://amplitude.com/explore/data/event-taxonomy)
- [PostHog Funnels docs](https://posthog.com/docs/product-analytics/funnels)
- [PostHog User Paths docs](https://posthog.com/docs/product-analytics/paths)
- [Conversion Funnel Analysis 2026 — UXCam](https://uxcam.com/blog/conversion-funnel-analysis/)
- [Mixpanel vs Amplitude Event Naming 2025 — WarpDriven](https://warpdriven.ai/en/blog/industry-1/mixpanel-vs-amplitude-event-naming-comparison-2025-48)
- [User Flow Analysis — Mixpanel blog](https://mixpanel.com/blog/user-flow-analysis/)
- [Cohort Retention Analysis Guide — Amplitude](https://amplitude.com/explore/analytics/cohort-retention-analysis)
- [NN/Group — Understanding User Pathways in Analytics](https://www.nngroup.com/articles/analytics-pathways/)

### Internal / conceptual reference
- Hermes Feature Store v2 PRD patterns: stat strip, filter rail, group-by, sort, three-persona tabs (LiveOps / Analyst / Engineer), provenance dots (🟢🟠⚪), health verdict card, threshold playground, handoff modal with Realtime / Batch warm / Batch cold latency tiers, use-case field on registration, snake_case ID + display-name pattern — referenced conceptually, no source code quoted.
- Cube semantic layer foundation: daily-aggregate cubes (`active_daily`, `recharge`, `mf_users`, `user_recharge_daily`) + view layer (`user_360`). Raw-event grain not yet exposed as a cube.

---

*End of report.*
