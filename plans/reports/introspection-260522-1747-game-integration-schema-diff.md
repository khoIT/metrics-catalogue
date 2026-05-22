# game_integration — schema diff and per-game cube YAMLs

Date: 2026-05-22 · Catalog: `game_integration` (Trino @ gio-gds-trino.vnggames.net:8080) · Schemas: `ballistar_vn` (baseline), `cfm_vn`, `jus_vn`, `ptg`, `muaw`, `pubgm`

## TL;DR

- `mf_users`, `std_ingame_user_active_daily`, `std_ingame_user_recharge_daily`
  — identical column shape across ballistar/cfm/jus/pubg. Cube YAMLs are
  byte-copies with only `title:` retitled.
- `etl_ingame_recharge` — **diverges in every game**. Five custom recharge
  cubes hand-mapped from real raw columns (one per non-baseline game).
- `ptg` and `muaw` have only the raw `etl_ingame_*` events. No `mf_users`,
  no `std_*`, no `cons_*`. Only `recharge` is feasible for each. PTG's
  latest data is **2026-04-30** (~3 weeks stale at time of introspection).
- Game key → schema map (in `cube/cube.js GAME_SCHEMA`):
  `ballistar→ballistar_vn`, `cfm→cfm_vn`, `jus→jus_vn`, `ptg→ptg`,
  `muaw→muaw`, `pubg→pubgm`.

## Table coverage

| Table | ballistar_vn | cfm_vn | jus_vn | ptg | muaw | pubgm |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| mf_users | ✅ 119 cols | ✅ same shape | ✅ same shape | ❌ absent | ❌ absent | ✅ same shape |
| std_ingame_user_active_daily | ✅ 43 cols | ✅ same (¹) | ✅ same | ❌ absent | ❌ absent | ✅ same |
| std_ingame_user_recharge_daily | ✅ 55 cols | ✅ same | ✅ same | ❌ absent | ❌ absent | ✅ same |
| etl_ingame_recharge | ✅ 20 cols (curated) | ⚠️ 31 cols (VNG SDK raw) | ⚠️ 54 cols (Netease raw) | ⚠️ 21 cols (camelCase raw) | ⚠️ 22 cols (clean curated) | ⚠️ 30 cols (VNG SDK + extras) |
| cons_* daily/monthly | ✅ present | ✅ present | ✅ present | ❌ absent | ❌ absent | ✅ present |
| mf_ingame_devices / mf_ingame_ips / mf_ingame_roles | ✅ | ✅ | ✅ | ❌ absent | ❌ absent | ✅ |

(¹) cfm_vn.std_ingame_user_active_daily uses `double` for `ingame_last_active_fighting_power` and `ingame_max_active_fighting_power` where ballistar/jus use `bigint`. Cube's `type: number` is type-agnostic — no YAML change needed.

## Recharge schema divergence (the work item)

### ballistar_vn.etl_ingame_recharge (20 cols, "curated etl")

Already modeled. Reference shape:
`log_type, account_id, role_id, role_name, country_code, transaction_id, money_type, product_id, charged_value, ingame_value, recharge_time, server_id, payment_channel, os_platform, is_first_recharge, add_info, log_date, log_month, folder_date, updated_time`

### cfm_vn.etl_ingame_recharge (31 cols, VNG SDK raw)

Canonical mapping locked into `cube/model/cubes/cfm/recharge.yml`:

| Ballistar canonical | CFM raw column |
|---|---|
| account_id (user_id) | `vopenid` |
| transaction_id | `vng_transaction` (primary) + `fsequence_no` exposed as alt |
| charged_value | `iamount` |
| value_usd | `imoney_us` |
| ingame_value | `imoney` |
| recharge_time | `event_time_with_timezone` |
| payment_channel | `payment_channel` (literal) + `pay_channel` raw exposed |
| server_id | `zoneid` (+ `zoneid2` kept hidden) |
| product_id | `productid` (+ `fofferid` as `offer_id`) |
| money_type / currency | `currency` |

CFM-specific extras kept: `sub_channel_id`, `login_channel`, `platid`, `user_type`, `value_source` (imoney_source), `fuin` (hidden).
Dropped (absent in CFM raw): `country_code`, `os_platform`, `is_first_recharge`, `role_*`, `vip_level`, `add_info`.

### jus_vn.etl_ingame_recharge (54 cols, Netease/JX raw)

Canonical mapping locked into `cube/model/cubes/jus/recharge.yml`:

| Ballistar canonical | JUS raw column |
|---|---|
| account_id (user_id) | `account_id` (literal) |
| transaction_id | `transid` |
| charged_value | `cash` |
| order_value | `order_cash` |
| ingame_value | `yuanbao` |
| recharge_time | `pay_time` |
| payment_channel | `pay_channel` |
| server_id | `server` |
| product_id | `prepaid_detail_item_id` (+ name + count) |
| money_type / currency | `currency` |
| country_code | `country_code` (literal) |
| os_platform | `os_name` (+ `os_ver` as `os_version`) |
| role_id / role_name / role_class / role_level | literal 1:1 |

JUS-specific extras kept: `pay_method`, `app_channel`, `jf_app_channel`, `app_version`, `device_model`, `network`, `isp`, `yuanbao_free_received`, `yuanbao_balance`, `yuanbao_free_balance`, `total_paypoint`, `is_emulator`, `is_root`.
Dropped (absent in JUS raw): `is_first_recharge`, `vip_level`, `money_type` (use `currency`).

### ptg.etl_ingame_recharge (21 cols, camelCase raw)

Canonical mapping locked into `cube/model/cubes/ptg/recharge.yml`. Cube has **no `mf_users` join** (no master profile table exists).

| Ballistar canonical | PTG raw column |
|---|---|
| account_id (user_id) | `accountid` (camelCase) |
| transaction_id | `transactionid` |
| charged_value | `chargedvalue` |
| ingame_value | `moneyvalueingame` (VARCHAR, mostly NULL in sample) |
| recharge_time | `rechargetime` (VARCHAR `'YYYY-MM-DD HH:MM:SS'`, parsed inline) |
| payment_channel | `paymentchannel` |
| os_platform | `osplatform` |
| server_id | `serverid` |
| money_type | `moneytype` |
| product_id | `productid` (+ `paymentitemid` as alt) |
| is_first_recharge | `isfirstcharge` |

PTG-specific extras kept: `gift_goldbar`, `gift_gem` (bonus currency granted with recharge), `money_value` (purpose distinct from chargedvalue — flagged for data-team confirmation), `first_recharges` measure.
Dropped (absent in PTG raw): `country_code`, `role_class`, `role_level`, `vip_level`.

### muaw.etl_ingame_recharge (22 cols, "clean curated")

Standalone cube — MUAW has no `mf_users` to join. Schema is closer to
ballistar's curated shape than to the VNG SDK / Netease raw shapes, with a
few naming quirks:

| Ballistar canonical | MUAW raw column |
|---|---|
| account_id (user_id) | `account_id` (literal) |
| transaction_id | `transaction_id` (literal) |
| charged_value | `charged_value` (literal) |
| recharge_time | `recharge_time` (already `timestamp with time zone`) |
| log_time | `log_time` — ETL ingest, exposed separately from recharge_time |
| payment_channel | `payment_channel` (literal) |
| os_platform | `platform_os` |
| money_type | `money_type` (literal) |
| product_id | `product_id` (literal) |
| role_id / role_name | literal 1:1 |
| role_class | `class` (bare) |
| role_level | `level` (bare) |
| vip_level | `vip_level` (literal) |
| is_first_recharge | `is_first_charge` — VARCHAR cast via `CASE WHEN ... = '1'` |

MUAW-specific extras kept: `recharge_total_money` (purpose unclear — flagged for data team), `client_ip` (hidden).
Dropped (absent in MUAW raw): `country_code`, `ingame_value`, `log_type`, `add_info`.

### pubgm.etl_ingame_recharge (30 cols, VNG SDK + extras)

VNG SDK family (same shape family as CFM), with two extra columns and one missing:

| Ballistar canonical | PUBG Mobile raw column |
|---|---|
| account_id (user_id) | `vopenid` |
| transaction_id | `fsequence_no` (no `vng_transaction` column here) |
| charged_value | `iamount` (bigint, not double) |
| value_usd | `imoney_us` |
| ingame_value | `imoney` (bigint) |
| recharge_time | `dteventtime` (UTC) |
| recharge_time_vn | `dteventtime_timezone_utc_7` (pre-adjusted UTC+7) |
| payment_channel | `pay_channel` (no curated `payment_channel` column) |
| server_id | `zoneid` (+ `zoneid2` hidden) |
| product_id | `product_id` (snake_case — different from cfm's `productid`!) |
| money_type / currency | `currency` |
| country_code | `country_code_adjust` ← extra vs cfm |

PUBG-specific extras kept: `recharge_time_vn` (already UTC+7), `country_code` (present unlike cfm), `sub_channel_id`, `login_channel`, `platid`, `user_type`, `offer_id` (fofferid), `value_source` (imoney_source), `fuin` (hidden).
Dropped (absent in PUBG raw): `vng_transaction`, `role_*`, `vip_level`, `is_first_recharge`.

## Type quirks handled

- `cfm_vn.std_ingame_user_active_daily.fighting_power` is `double` (vs `bigint` in ballistar/jus). Cube `type: number` is shape-agnostic; no YAML change.
- `ptg.rechargetime` is `varchar 'YYYY-MM-DD HH:MM:SS'` with no timezone. Parsed via the existing ballistar pattern: `from_iso8601_timestamp(REPLACE({CUBE}.rechargetime, ' ', 'T') || 'Z')`. Assumes UTC.
- `ptg.moneyvalueingame` is `varchar` (mostly NULL in sample). Exposed as string; needs an explicit `CAST` to use numerically.
- `muaw.is_first_charge` is `varchar` (not bigint/integer like ballistar's `is_first_recharge`). Compared to `'1'` in the CASE expression — sample data to confirm the value space.
- `pubgm.iamount` and `pubgm.imoney` are `bigint` (cfm has `double` for the same columns). Cube `type: number` handles both.

## Repo layout after this change

```
cube/model/
├── cubes/
│   ├── ballistar/                # 4 files moved here (no content change beyond title)
│   ├── cfm/                       # 4 files; 3 byte-copies + recharge.yml hand-mapped
│   ├── jus/                       # 4 files; same pattern as cfm
│   ├── ptg/                       # standalone — only recharge.yml (no mf_users join)
│   ├── muaw/                      # standalone — only recharge.yml (no mf_users join)
│   └── pubg/                      # 4 files; 3 byte-copies + recharge.yml hand-mapped
└── views/
    └── ballistar/                  # moved from views/user_360.yml; per-game views are phase 2
        └── user_360.yml
```

`cube/cube.js` adds `repositoryFactory` that loads `cubes/<game>/` + `views/<game>/` per tenant (missing dirs tolerated, so cfm/jus/ptg/muaw/pubg with no views compile fine). `GAME_SCHEMA` now maps 6 games: `ballistar→ballistar_vn`, `cfm→cfm_vn`, `jus→jus_vn`, `ptg→ptg`, `muaw→muaw`, `pubg→pubgm`.

## Cleanup also done

- Deleted `cube/model/cubes/mf_users.yml.bak` (orphaned backup).
- Dropped wizard-artifact measures `asd` and `test` from cfm + jus + pubg copies of `mf_users.yml`. Left intact in ballistar (original committed state).

## Verification

- `node --check cube/cube.js` — pass
- `node --check cube/auth-db.js` — pass
- All 16 YAML files parse cleanly under `ruby -ryaml -e ...`
- Trino reachable on `gio-gds-trino.vnggames.net:8080` (HTTPS) via VPN
- Introspection helper: `examples/trino_introspect.py` (new, honours `TRINO_PORT`)

## Open questions

### Revenue-column semantics (confirm with data team)

1. **CFM `iamount` currency**: is iamount always VND for VN users, or does `currency` ever differ? The `currency` dimension is exposed and the `vnd_only` segment guards against this — confirm with data team if a VN user can ever have currency=USD here.
2. **PUBG Mobile `iamount` currency**: same question as CFM — does `currency` ever differ from VND for VN users? Same `vnd_only` segment provided.
3. **JUS `cash` vs `order_cash`**: which is the canonical revenue figure? Modeled `cash` as `revenue_vnd` and `order_cash` as `order_value`. If discounts/promos make these differ in practice, reporting needs to pick one.
4. **PTG `moneyvalue` vs `chargedvalue`**: both are `double`. Modeled `chargedvalue` as revenue. Purpose of `moneyvalue` unclear (rate? alt currency? legacy?) — flagged in YAML description; needs data-team confirmation.
5. **MUAW `recharge_total_money` vs `charged_value`**: both are `double`. Modeled `charged_value` as revenue. Purpose of `recharge_total_money` unclear (running total? multi-item recharge sum?) — needs data-team confirmation.

### Data shape / value-space confirmations

6. **MUAW `is_first_charge` value space**: the column is `varchar` (vs integer in ballistar's `is_first_recharge`). Cast as `'1'` = true; sample data to confirm — could also be `'Y'`/`'N'` or some other encoding.
7. **PTG data freshness**: last `log_date` is 2026-04-30, ~3 weeks behind today. Is the ETL pipeline running for PTG, or is it paused?
8. **MUAW data freshness / coverage**: did not check the latest `log_date` for muaw — recommend a similar freshness probe before relying on it for reporting.
9. **PUBG `recharge_time_vn` vs `recharge_time`**: source pre-adjusts `dteventtime` to UTC+7 in `dteventtime_timezone_utc_7`. Confirm this column is reliably populated (not NULL-ish for older rows) before consumers depend on it for VN-local reporting.
10. **PUBG `country_code_adjust`**: exposed as `country_code` dimension. Confirm this is the post-fraud-correction country (as the name suggests) vs raw — affects which one belongs in reports.

### Extras not yet modeled (potential phase-2 cubes)

11. **CFM extras**: `etl_ingame_match_net_work_stats`, `etl_ingame_room_*`, `etl_ingame_team_*` — FPS match-flow data. Could feed a future `gameplay_match` cube.
12. **JUS extras**: `etl_ingame_ccu`, `etl_ingame_item_flow`, `etl_ingame_money_flow`. Could feed economy/concurrency cubes.
13. **PUBG extras**: `etl_ingame_uc_flow` — in-game UC (currency) flow. Could feed an economy cube.
14. **MUAW / PTG raw events**: `etl_ingame_login`, `etl_ingame_logout`, `etl_ingame_register` exist for both. Could synthesize a partial `active_daily`-shape cube (logins-per-user-per-day) until upstream populates the real `std_*` tables.

### Structural follow-ups

15. **Views for non-ballistar games**: only ballistar has a `user_360` view post-restructure. Need per-game views built in phase 2 (under `cube/model/views/<game>/`) if BI tools should query non-ballistar games via a view. PTG and MUAW can't replicate user_360 anyway (no mf_users / std_ tables).
16. **Game-key vs schema-name divergence**: `pubg→pubgm` and `ballistar→ballistar_vn` already diverge. JWT consumers must use the GAME KEY (`pubg`, `ballistar`), not the schema name. Worth a one-liner in the README pointing this out.
