-- =============================================================================
-- 06_cohort_analysis.sql
-- Purpose : Monthly signup cohorts and a retention-heatmap source table
--           (cohort_month x months_since_signup -> retention %), the shape
--           a BI tool (Power BI, Looker, Tableau) needs to render a cohort
--           heatmap directly.
-- Tables  : users, events
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Monthly signup cohort sizes
-- -----------------------------------------------------------------------------
SELECT
    strftime('%Y-%m', signup_date) AS cohort_month,
    COUNT(*)                       AS cohort_size
FROM users
GROUP BY cohort_month
ORDER BY cohort_month;

-- -----------------------------------------------------------------------------
-- 2. Cohort retention heatmap source table
--    Grain: one row per (cohort_month, months_since_signup).
--    retained_users = distinct users from that cohort active in that period.
--    retention_pct   = retained_users / cohort_size.
--    Feed this table directly into a BI pivot/heatmap visual.
-- -----------------------------------------------------------------------------
WITH cohorts AS (
    SELECT
        user_id,
        strftime('%Y-%m', signup_date)                                   AS cohort_month,
        CAST(strftime('%Y', signup_date) AS INTEGER) * 12
            + CAST(strftime('%m', signup_date) AS INTEGER)               AS cohort_month_index
    FROM users
),
activity AS (
    SELECT
        e.user_id,
        CAST(strftime('%Y', e.event_date) AS INTEGER) * 12
            + CAST(strftime('%m', e.event_date) AS INTEGER)              AS event_month_index
    FROM events AS e
    GROUP BY e.user_id, event_month_index
),
cohort_activity AS (
    SELECT
        c.cohort_month,
        c.user_id,
        a.event_month_index - c.cohort_month_index AS months_since_signup
    FROM cohorts AS c
    JOIN activity AS a ON a.user_id = c.user_id
    WHERE a.event_month_index >= c.cohort_month_index
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM cohorts
    GROUP BY cohort_month
)
SELECT
    ca.cohort_month,
    ca.months_since_signup,
    cs.cohort_size,
    COUNT(DISTINCT ca.user_id)                                        AS retained_users,
    ROUND(100.0 * COUNT(DISTINCT ca.user_id) / cs.cohort_size, 1)      AS retention_pct
FROM cohort_activity AS ca
JOIN cohort_sizes AS cs ON cs.cohort_month = ca.cohort_month
GROUP BY ca.cohort_month, ca.months_since_signup, cs.cohort_size
ORDER BY ca.cohort_month, ca.months_since_signup;

-- -----------------------------------------------------------------------------
-- 3. Cohort revenue table: cumulative revenue per cohort by months since
--    signup (revenue-based cohort curve, useful for LTV trend analysis)
-- -----------------------------------------------------------------------------
WITH cohorts AS (
    SELECT
        user_id,
        strftime('%Y-%m', signup_date)                     AS cohort_month,
        CAST(strftime('%Y', signup_date) AS INTEGER) * 12
            + CAST(strftime('%m', signup_date) AS INTEGER) AS cohort_month_index
    FROM users
),
bookings AS (
    SELECT
        user_id,
        revenue,
        CAST(strftime('%Y', event_date) AS INTEGER) * 12
            + CAST(strftime('%m', event_date) AS INTEGER)  AS event_month_index
    FROM events
    WHERE event_name = 'booking_completed'
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size FROM cohorts GROUP BY cohort_month
)
SELECT
    c.cohort_month,
    b.event_month_index - c.cohort_month_index                  AS months_since_signup,
    cs.cohort_size,
    ROUND(SUM(b.revenue), 2)                                    AS revenue_eur,
    ROUND(SUM(b.revenue) / cs.cohort_size, 2)                   AS revenue_per_cohort_user_eur
FROM cohorts AS c
JOIN bookings AS b ON b.user_id = c.user_id AND b.event_month_index >= c.cohort_month_index
JOIN cohort_sizes AS cs ON cs.cohort_month = c.cohort_month
GROUP BY c.cohort_month, months_since_signup, cs.cohort_size
ORDER BY c.cohort_month, months_since_signup;
