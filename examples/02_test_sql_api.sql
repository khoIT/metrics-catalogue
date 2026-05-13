-- =============================================================================
-- SQL API examples — Cube exposes a Postgres-compatible wire protocol on
-- :15432, so any tool that speaks Postgres (psql, Tableau, Metabase, DBeaver,
-- DataGrip, Python psycopg2, JDBC clients) can connect.
--
-- Connection:
--   psql -h localhost -p 15432 -U cube -d cube
--   (password = cube, set in .env)
--
-- Key syntactic quirks vs raw SQL:
--   * Aggregates on Cube measures must be wrapped in MEASURE(...)  — Cube
--     uses this to identify the measure and route to pre-aggregations.
--   * Views are tables, dimensions are columns, measures are columns wrapped
--     in MEASURE(). Segments are exposed as boolean columns.
--   * Time arithmetic uses standard SQL (INTERVAL '7' DAY, DATE_TRUNC, etc.).
-- =============================================================================


-- Q1 — Top 10 countries by user count
SELECT
  country,
  MEASURE(user_count_approx) AS users
FROM user_360
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;


-- Q2 — Payer tier breakdown for VN users
SELECT
  payer_tier,
  MEASURE(user_count_approx) AS users,
  MEASURE(ltv_total_vnd)     AS gross_revenue_vnd,
  MEASURE(arppu_vnd)         AS arppu_vnd
FROM user_360
WHERE vn_users = TRUE          -- segment as boolean
GROUP BY 1
ORDER BY 3 DESC;


-- Q3 — Audience build: VN whales at risk (one row per user, no aggregation)
-- This is the segmentation export — feed user_id list to push notification,
-- A/B bucketing, ML feature pipeline, etc.
SELECT
  user_id,
  ltv_vnd,
  days_since_last_active,
  lifecycle_stage,
  last_role_class
FROM user_360
WHERE vn_users = TRUE
  AND whales = TRUE
  AND at_risk_paying = TRUE
ORDER BY ltv_vnd DESC
LIMIT 1000;


-- Q4 — DAU trend last 30 days by OS
SELECT
  log_date,
  os_platform,
  MEASURE(dau) AS dau
FROM activity_metrics
WHERE log_date >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY 1, 2
ORDER BY 1, 2;


-- Q5 — Revenue last 7d by channel + country
SELECT
  payment_channel,
  country_code,
  MEASURE(revenue_vnd)   AS revenue,
  MEASURE(transactions)  AS txns,
  MEASURE(paying_users)  AS payers,
  MEASURE(arppu_vnd)     AS arppu
FROM revenue_metrics
WHERE recharge_time >= CURRENT_TIMESTAMP - INTERVAL '7' DAY
GROUP BY 1, 2
ORDER BY 3 DESC;


-- Q6 — Behavioral cohort: VN paying users with >= 7 active days in last 14
-- AND lifetime LTV >= 500K. (Compose multiple segments + numeric filters.)
SELECT
  user_id,
  ltv_vnd,
  total_active_days,
  max_role_level
FROM user_360
WHERE vn_users = TRUE
  AND paying_lifetime = TRUE
  AND ltv_30d_vnd >= 500000
  AND total_active_days >= 30      -- proxy for "engaged"
ORDER BY ltv_vnd DESC
LIMIT 5000;


-- Q7 — Cohort retention proxy: install_month vs lifecycle_stage
SELECT
  install_month,
  lifecycle_stage,
  MEASURE(user_count_approx) AS users
FROM user_360
WHERE install_month >= '2026-01'
GROUP BY 1, 2
ORDER BY 1, 2;


-- Q8 — Inspect a single user (debugging audience matching)
SELECT *
FROM user_360
WHERE user_id = '3368303345288667136';


-- Q9 — Save a segment as a "view" on the consumer side
-- (Pure SQL, no Cube extension.)
WITH vn_whales_at_risk AS (
  SELECT user_id, ltv_vnd, days_since_last_active
  FROM user_360
  WHERE vn_users = TRUE
    AND whales = TRUE
    AND at_risk_paying = TRUE
)
SELECT
  CASE
    WHEN days_since_last_active <= 14 THEN 'risk_7_14d'
    ELSE 'risk_15_30d'
  END AS bucket,
  COUNT(*) AS users,
  SUM(ltv_vnd) AS exposure_vnd
FROM vn_whales_at_risk
GROUP BY 1;
