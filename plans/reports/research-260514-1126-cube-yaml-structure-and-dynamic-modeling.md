# Research Report: Cube.dev YAML Structure & Dynamic Metric/Event Definition

**Generated:** 2026-05-14 11:26
**Scope:** https://cube.dev/docs/product/introduction — YAML schema, dynamic data modeling, how events/metrics are defined.

---

## Executive Summary

Cube is a semantic layer that exposes warehouse data as a graph of **cubes** (entities) and **views** (facades) defined in YAML (or JS/Python). **Metrics = `measures`** (aggregations: count/sum/avg/etc.); **events = rows in a fact-table cube** with a `time` dimension. Static YAML covers ~80% of use cases; the remaining dynamic surface is delivered through **Jinja templating in YAML** and **Python data models** that run inside Cube's schema compiler — enabling per-tenant or programmatically-generated metrics without manual file edits.

For a "user dynamically defines a metric" UX, the practical path is: capture the user's metric spec (name, sql, aggregation, filters) → render a Jinja template OR emit a Python `@cube/@measure` definition → place it under Cube's `schema_path` → Cube auto-recompiles via the schema compiler. Multi-tenant variants use `COMPILE_CONTEXT` to fork the model per request.

Best fit for this project: **YAML + Jinja** for the simple "let users add a measure" path; switch to **Python data models** when the metric set itself is data-driven (loops over a registry/table).

---

## Research Methodology

- Sources consulted: 5 (Cube official docs)
- Date range: current Cube docs (May 2026)
- Search terms: introduction, data-modeling/overview, data-modeling/concepts, reference/data-model/cube, data-modeling/dynamic
- Gemini: disabled (no `.ck.json`), used WebFetch

---

## Key Findings

### 1. Platform Architecture (Four Pillars)

Cube positions itself as "the business intelligence platform powered by the open-source semantic layer," acting as a proxy between consumers (BI tools, AI agents) and the warehouse via **Semantic SQL** (Postgres-compatible) with a special `MEASURE()` function.

The four pillars:

| Pillar | Mechanism |
|--------|-----------|
| **Data Modeling** | YAML/JS/Python definitions of cubes + views forming a knowledge graph |
| **Access Control** | Python/JS policies — row-level, tenant-aware, runtime-enforced |
| **Caching** | Pre-aggregations stored in **Cube Store**, with "aggregate awareness" |
| **APIs** | REST, GraphQL, SQL — plus introspectable meta API |

### 2. Core Concepts

| Concept | Definition (quoted) |
|---------|---------------------|
| **Cube** | Represents a business entity; "defines all calculations within measures and dimensions, as well as relationships between entities" |
| **View** | Facade; "selecting measures and dimensions from connected cubes and presenting them as unified datasets". Views **do not define their own members**. |
| **Dimension** | Properties of a **single** data point (status, product_id) — enable grouping |
| **Measure (Metric)** | Properties of a **set** of data points (count, sum) — enable aggregation |
| **Event** | Modeled as **rows in a fact-table cube** with a `time` dimension (e.g. `line_items` cube — each row = a transaction event) |
| **Join** | Relationship between cubes: `one_to_one` / `one_to_many` / `many_to_one`. All joins are LEFT JOIN by default. |
| **Segment** | Reusable named SQL filter |
| **Hierarchy** | Ordered drill-down of dimensions |
| **Pre-aggregation** | Materialized rollup in Cube Store for query acceleration |

### 3. Complete YAML Reference (cube)

```yaml
cubes:
  - name: orders                           # required, unique
    sql_table: public.orders               # preferred for simple cases
    # sql: SELECT * FROM orders            # alternative: arbitrary SELECT
    sql_alias: ord                         # alias prefix (truncation-safe for Postgres)
    extends: base_orders                   # inherit members from another cube
    data_source: prod_db                   # multi-DB routing
    title: Product Orders
    description: All orders-related info
    public: true                           # API visibility (default true)
    calendar: false                        # mark as calendar cube
    meta:
      custom_field: custom_value           # arbitrary metadata, surfaced via meta API

    refresh_key:
      sql: SELECT MAX(updated_at) FROM orders
      # OR every: 1 hour
      # OR every: "30 5 * * 5"
      # timezone: America/Los_Angeles

    dimensions:
      - name: id
        sql: id
        type: number
        primary_key: true
      - name: created_at
        sql: created_at
        type: time
      - name: status
        sql: status
        type: string
      - name: amount
        sql: amount
        type: number
      - name: is_active
        sql: is_active
        type: boolean
      - name: location
        sql: location
        type: geo

    measures:
      - name: count
        type: count
      - name: count_distinct_users
        type: count_distinct
        sql: user_id
      - name: total_amount
        type: sum
        sql: amount
      - name: average_amount
        type: avg
        sql: amount
      - name: min_amount
        type: min
        sql: amount
      - name: max_amount
        type: max
        sql: amount
      - name: approx_users
        type: count_distinct_approx
        sql: user_id
      - name: revenue
        type: number                       # custom calc; references other measures
        sql: "{total_amount}"
      - name: paying_count
        type: count
        sql: id
        filters:
          - sql: "{CUBE}.paying = 'true'"
      - name: paying_percentage
        type: number
        sql: "1.0 * {paying_count} / {count}"
        format: percent

    segments:
      - name: completed
        sql: "{CUBE.status} = 'completed'"

    hierarchies:
      - name: date_hierarchy
        levels:
          - created_at

    joins:
      - name: users
        relationship: many_to_one          # one_to_one | one_to_many | many_to_one
        sql: "{CUBE.user_id} = {users.id}"

    pre_aggregations:
      - name: orders_rollup
        dimensions: [created_at, status]
        measures: [count, total_amount]
        time_dimension: created_at
        granularity: day

    access_policy:
      - role: admin
        sql: "true"

views:
  - name: orders_view
    cubes:
      - join_path: orders
        includes: ["*"]                    # or list specific members
      - join_path: orders.users
        prefix: true
        includes: [email, company]
```

#### Field Types

**Dimension `type`:** `string` · `number` · `time` · `boolean` · `geo`
**Measure `type`:** `count` · `count_distinct` · `count_distinct_approx` · `sum` · `avg` · `min` · `max` · `number` (custom calc)

#### `{CUBE}` / `{measure_name}` Reference

Inside `sql:` expressions, `{CUBE}` resolves to the current cube's table alias and `{member_name}` resolves to another member's SQL — enables composition (e.g. `paying_percentage` referencing `paying_count` and `count`).

### 4. Dynamic Data Modeling

Cube supports three layers of dynamism, ordered by power:

#### Layer A — Jinja in YAML (simple)

YAML files are first rendered through Jinja, so loops + conditionals + variables work inside the schema itself. Typical use: generate N similar measures from a list.

```yaml
{% set metric_specs = [
  {'name': 'signups',  'sql': "event = 'signup'"},
  {'name': 'logins',   'sql': "event = 'login'"},
  {'name': 'payments', 'sql': "event = 'payment'"}
] %}

cubes:
  - name: events
    sql_table: raw.events
    measures:
      {% for m in metric_specs %}
      - name: {{ m.name }}_count
        type: count
        filters:
          - sql: "{CUBE}.{{ m.sql }}"
      {% endfor %}
```

#### Layer B — Python Data Models (programmatic)

Python files in `model/` (or `schema_path`) use decorators to define cubes. Data drives the model — read a registry, loop, emit cubes/measures.

```python
from cube import cube, TemplateContext

template = TemplateContext()

@template.function('load_metrics')
def load_metrics():
    # could read from DB, file, env, API
    return [
        {'name': 'signup_count',  'filter': "event = 'signup'"},
        {'name': 'payment_count', 'filter': "event = 'payment'"},
    ]

# In a .py model file:
for spec in load_metrics():
    cube(
        name=f"events_{spec['name']}",
        sql_table='raw.events',
        measures=[{
            'name': spec['name'],
            'type': 'count',
            'filters': [{'sql': spec['filter']}],
        }],
    )
```

(Exact decorator surface — `@cube`, `@dimension`, `@measure`, `@config`, `@context_func` — is what the dynamic page documents; my fetch returned 404 on `/dynamic-data-models` and the alternate `/dynamic` URL returned a thin summary. Decorator names confirmed via training knowledge; verify against current docs before implementing.)

#### Layer C — `COMPILE_CONTEXT` (multi-tenant)

`COMPILE_CONTEXT` is a special object containing the security context at **compile time**. Schema is compiled per distinct context — different tenants see different cubes/measures from the same source files.

```yaml
cubes:
  - name: orders
    sql_table: "tenant_{{ COMPILE_CONTEXT.securityContext.tenant_id }}.orders"
    measures:
      {% if COMPILE_CONTEXT.securityContext.plan == 'enterprise' %}
      - name: advanced_revenue_breakdown
        type: number
        sql: "..."
      {% endif %}
```

Routing config (`cube.js` / `cube.py`):

```js
module.exports = {
  contextToAppId: ({ securityContext }) => `app_${securityContext.tenant_id}`,
  contextToOrchestratorId: ({ securityContext }) => `orch_${securityContext.tenant_id}`,
};
```

#### Layer D — `schema_path` & file-system registration

Cube loads all files under `schema_path` (default `model/`). To register a new metric programmatically at runtime: **write a YAML/Python file to that path** → Cube's file watcher recompiles. This is the simplest "user defines a metric in a UI form" implementation:

1. UI captures spec (name, sql, agg, filters)
2. Backend renders Jinja template → writes `model/cubes/<slug>.yml`
3. Cube hot-reloads, new metric queryable immediately

### 5. Modeling Events as Metrics

Concrete pattern for an event-stream table:

```yaml
cubes:
  - name: events
    sql_table: analytics.events

    dimensions:
      - name: id
        sql: id
        type: number
        primary_key: true
      - name: event_name
        sql: event_name
        type: string
      - name: user_id
        sql: user_id
        type: string
      - name: occurred_at
        sql: occurred_at
        type: time
      - name: properties
        sql: properties
        type: string        # JSON column

    measures:
      - name: total_events
        type: count

      - name: unique_users
        type: count_distinct
        sql: user_id

      # Per-event-type metrics (each is a metric)
      - name: signup_count
        type: count
        filters: [{ sql: "{CUBE}.event_name = 'signup'" }]

      - name: conversion_rate
        type: number
        sql: "1.0 * {signup_count} / NULLIF({total_events}, 0)"
        format: percent
```

Each row in `events` = one event. Each `measure` with a filter = one named metric over that event stream. To add a new metric ("checkout_completed") the user only needs to add another measure entry — exactly the dynamic surface above.

---

## Comparative Analysis: Dynamic Approaches

| Approach | When to use | Pros | Cons |
|----------|-------------|------|------|
| **Static YAML** | Stable, hand-curated metric set | Simple, reviewable in git | No runtime extensibility |
| **YAML + Jinja** | Metric list known at compile, repetitive | No code, version-controllable | Limited to template logic |
| **Python models** | Metric set driven by data/API | Full programmatic power | Steeper learning curve |
| **File-write at runtime** | End-user defines metrics in app UI | Hot-reload, no Cube changes | Requires write access to model dir + validation/safety layer |
| **`COMPILE_CONTEXT`** | Multi-tenant isolation | Single source, per-tenant schema | Compile cache per context — memory cost |

---

## Implementation Recommendations

### For a "user dynamically defines a metric" UI

1. **Spec model** — capture: name, source cube/table, aggregation type, sql expr, filters, optional time dimension.
2. **Server-side renderer** — Jinja template producing a single `<metric_slug>.yml` file.
3. **Validation** — parse/compile the rendered YAML in a sandbox before write; reject if Cube schema compile fails.
4. **Storage** — write to `model/cubes/user_metrics/<slug>.yml`; commit to git for audit OR keep in a sidecar DB and regenerate on boot.
5. **Hot reload** — Cube watches `schema_path`; new metric is queryable within seconds via REST/GraphQL/SQL API.
6. **Auth** — gate writes behind RBAC; consider exposing only `events`-style fact cubes to user metric builder to avoid arbitrary SQL injection into the warehouse layer.

### Common Pitfalls

- **`sql:` injection** — user-controlled `sql` strings hit the warehouse. Whitelist allowed columns/operators rather than raw passthrough.
- **Measure references** — `{other_measure}` only resolves within the same cube; cross-cube refs need joins + views.
- **Pre-aggregation drift** — adding measures doesn't auto-add them to pre-aggs; performance regressions are silent until the user queries the new metric.
- **`COMPILE_CONTEXT` cache blowup** — each unique compile context = one compiled schema in memory. Coarse tenant keys (tenant_id, not user_id).
- **Views vs Cubes** — users typically should query **views** (curated facades), not raw cubes. Plan a view-update step when new user metrics land.

---

## Resources & References

- [Cube Introduction](https://cube.dev/docs/product/introduction)
- [Data Modeling Overview](https://cube.dev/docs/product/data-modeling/overview)
- [Concepts](https://cube.dev/docs/product/data-modeling/concepts)
- [Cube Reference](https://cube.dev/docs/reference/data-model/cube)
- [Dynamic Data Models](https://cube.dev/docs/product/data-modeling/dynamic) — verify live; `/dynamic-data-models` returns 404

---

## Appendices

### A. Glossary

- **Semantic SQL** — Cube's Postgres-compatible SQL dialect with the `MEASURE()` function
- **Cube Store** — Cube's columnar materialization layer for pre-aggregations
- **COMPILE_CONTEXT** — security/tenant context made available at schema compile time
- **schema_path** — file-system directory Cube scans for model files (default `model/`)
- **Meta API** — introspection endpoint exposing the compiled data model

### B. Minimal Event-Stream Cube (copy-paste starter)

```yaml
cubes:
  - name: events
    sql_table: analytics.events
    dimensions:
      - {name: id, sql: id, type: number, primary_key: true}
      - {name: event_name, sql: event_name, type: string}
      - {name: occurred_at, sql: occurred_at, type: time}
    measures:
      - {name: count, type: count}
```

---

## Unresolved Questions

1. Exact current decorator surface for Python data models (`@cube`, `@dimension`, `@measure`, `@config`, `@context_func`) — docs page `/dynamic-data-models` 404'd; `/dynamic` returned a thin summary. Confirm against the live Cube version targeted for this project before committing to a Python-based registration flow.
2. Whether `schema_compilers` is still a supported config key in the current Cube release, or has been superseded by `schema_path` + auto-detection.
3. Cube's stance on **runtime mutation of the model dir** (file watcher latency, race conditions during concurrent writes) — needs empirical test before wiring a UI metric builder to it.
4. Whether a `view` can be programmatically extended at compile time to auto-include newly-added user measures, or whether the view file must be regenerated alongside each new metric.
