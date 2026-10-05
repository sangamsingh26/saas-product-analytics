-- =============================================================================
-- 03_kpi_dashboard.sql
-- Purpose : Core product KPIs — the numbers that would sit at the top of a
--           weekly/monthly business review deck.
-- Definitions used throughout this project:
--   Activation = >=1 search_completed AND >=1 booking_completed within 7 days
--                of signup_date.
--   Conversion = >=1 booking_completed event, ever.
--   Active user (period) = >=1 event recorded in that period.
-- Tables  : users, events, experiments
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Total users and total ever-active users (>=1 event, any time)
-- -----------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM users)                                  AS total_users,
    (SELECT COUNT(DISTINCT user_id) FROM events)                  AS ever_active_users,
    ROUND(
        100.0 * (SELECT COUNT(DISTINCT user_id) FROM events) / (SELECT COUNT(*) FROM users), 1
    )                                                              AS pct_ever_active;

-- -----------------------------------------------------------------------------
-- 2. Daily Active Users (DAU) trend
-- -----------------------------------------------------------------------------
SELECT
    event_date,
    COUNT(DISTINCT user_id) AS dau
FROM events
GROUP BY event_date
ORDER BY event_date;

-- -----------------------------------------------------------------------------
-- 3. Weekly Active Users (WAU) trend (ISO-ish week bucket via strftime %W)
-- -----------------------------------------------------------------------------
SELECT
    strftime('%Y-W%W', event_date) AS iso_week,
    MIN(event_date)                AS week_start_sample,
    COUNT(DISTINCT user_id)        AS wau
FROM events
GROUP BY iso_week
ORDER BY iso_week;

-- -----------------------------------------------------------------------------
-- 4. Monthly Active Users (MAU) trend
-- -----------------------------------------------------------------------------
SELECT
    strftime('%Y-%m', event_date) AS month,
    COUNT(DISTINCT user_id)       AS mau
FROM events
GROUP BY month
ORDER BY month;

-- -----------------------------------------------------------------------------
-- 5. Stickiness ratio (avg DAU / MAU) per month — a standard engagement KPI
-- -----------------------------------------------------------------------------
WITH daily AS (
    SELECT
        strftime('%Y-%m', event_date) AS month,
        event_date,
        COUNT(DISTINCT user_id)       AS dau
    FROM events
    GROUP BY month, event_date
),
monthly AS (
    SELECT
        strftime('%Y-%m', event_date) AS month,
        COUNT(DISTINCT user_id)       AS mau
    FROM events
    GROUP BY month
)
SELECT
    d.month,
    ROUND(AVG(d.dau), 1)                                   AS avg_dau,
    m.mau,
    ROUND(100.0 * AVG(d.dau) / m.mau, 1)                   AS stickiness_pct
FROM daily AS d
JOIN monthly AS m ON d.month = m.month
GROUP BY d.month, m.mau
ORDER BY d.month;

-- -----------------------------------------------------------------------------
-- 6. Activation rate: >=1 search_completed AND >=1 booking_completed within
--    7 days of signup_date
-- -----------------------------------------------------------------------------
WITH activation_events AS (
    SELECT
        e.user_id,
        MAX(CASE WHEN e.event_name = 'search_completed'   THEN 1 ELSE 0 END) AS did_search,
        MAX(CASE WHEN e.event_name = 'booking_completed'  THEN 1 ELSE 0 END) AS did_booking
    FROM events AS e
    JOIN users AS u ON e.user_id = u.user_id
    WHERE julianday(e.event_date) - julianday(u.signup_date) BETWEEN 0 AND 7
    GROUP BY e.user_id
),
activated AS (
    SELECT user_id FROM activation_events WHERE did_search = 1 AND did_booking = 1
)
SELECT
    (SELECT COUNT(*) FROM users)          AS total_users,
    (SELECT COUNT(*) FROM activated)      AS activated_users,
    ROUND(100.0 * (SELECT COUNT(*) FROM activated) / (SELECT COUNT(*) FROM users), 2) AS activation_rate_pct;

-- -----------------------------------------------------------------------------
-- 7. Conversion rate: >=1 booking_completed event, ever
-- -----------------------------------------------------------------------------
WITH converted_users AS (
    SELECT DISTINCT user_id
    FROM events
    WHERE event_name = 'booking_completed'
)
SELECT
    (SELECT COUNT(*) FROM users)             AS total_users,
    (SELECT COUNT(*) FROM converted_users)   AS converted_users,
    ROUND(100.0 * (SELECT COUNT(*) FROM converted_users) / (SELECT COUNT(*) FROM users), 2) AS conversion_rate_pct;

-- -----------------------------------------------------------------------------
-- 8. Revenue KPIs: total revenue, ARPU, average booking value (AOV),
--    bookings per user
-- -----------------------------------------------------------------------------
WITH bookings AS (
    SELECT user_id, revenue
    FROM events
    WHERE event_name = 'booking_completed'
)
SELECT
    ROUND(SUM(b.revenue), 2)                                        AS total_revenue_eur,
    ROUND(SUM(b.revenue) / (SELECT COUNT(*) FROM users), 2)         AS arpu_eur,               -- revenue / ALL users
    ROUND(SUM(b.revenue) / COUNT(DISTINCT b.user_id), 2)            AS arppu_eur,               -- revenue / paying users
    ROUND(AVG(b.revenue), 2)                                        AS avg_booking_value_eur,   -- AOV
    ROUND(1.0 * COUNT(*) / (SELECT COUNT(*) FROM users), 2)         AS bookings_per_user_overall,
    ROUND(1.0 * COUNT(*) / COUNT(DISTINCT b.user_id), 2)            AS bookings_per_paying_user
FROM bookings AS b;

-- -----------------------------------------------------------------------------
-- 9. Revenue by country
-- -----------------------------------------------------------------------------
SELECT
    u.country,
    COUNT(e.event_id)                                        AS completed_bookings,
    ROUND(SUM(e.revenue), 2)                                 AS revenue_eur,
    ROUND(SUM(e.revenue) / COUNT(DISTINCT u.user_id), 2)     AS arpu_eur,
    ROUND(AVG(e.revenue), 2)                                 AS avg_booking_value_eur
FROM users AS u
LEFT JOIN events AS e
       ON e.user_id = u.user_id AND e.event_name = 'booking_completed'
GROUP BY u.country
ORDER BY revenue_eur DESC;

-- -----------------------------------------------------------------------------
-- 10. Revenue by platform
-- -----------------------------------------------------------------------------
SELECT
    u.platform,
    COUNT(e.event_id)                                        AS completed_bookings,
    ROUND(SUM(e.revenue), 2)                                 AS revenue_eur,
    ROUND(SUM(e.revenue) / COUNT(DISTINCT u.user_id), 2)     AS arpu_eur,
    ROUND(AVG(e.revenue), 2)                                 AS avg_booking_value_eur
FROM users AS u
LEFT JOIN events AS e
       ON e.user_id = u.user_id AND e.event_name = 'booking_completed'
GROUP BY u.platform
ORDER BY revenue_eur DESC;

-- -----------------------------------------------------------------------------
-- 11. Revenue by acquisition channel
-- -----------------------------------------------------------------------------
SELECT
    u.acquisition_channel,
    COUNT(e.event_id)                                        AS completed_bookings,
    ROUND(SUM(e.revenue), 2)                                 AS revenue_eur,
    ROUND(SUM(e.revenue) / COUNT(DISTINCT u.user_id), 2)     AS arpu_eur,
    ROUND(AVG(e.revenue), 2)                                 AS avg_booking_value_eur
FROM users AS u
LEFT JOIN events AS e
       ON e.user_id = u.user_id AND e.event_name = 'booking_completed'
GROUP BY u.acquisition_channel
ORDER BY revenue_eur DESC;

-- -----------------------------------------------------------------------------
-- 12. Single-row executive KPI summary (all core numbers in one place)
-- -----------------------------------------------------------------------------
WITH activation_events AS (
    SELECT
        e.user_id,
        MAX(CASE WHEN e.event_name = 'search_completed'  THEN 1 ELSE 0 END) AS did_search,
        MAX(CASE WHEN e.event_name = 'booking_completed' THEN 1 ELSE 0 END) AS did_booking
    FROM events AS e
    JOIN users AS u ON e.user_id = u.user_id
    WHERE julianday(e.event_date) - julianday(u.signup_date) BETWEEN 0 AND 7
    GROUP BY e.user_id
),
bookings AS (
    SELECT user_id, revenue FROM events WHERE event_name = 'booking_completed'
)
SELECT
    (SELECT COUNT(*) FROM users)                                             AS total_users,
    (SELECT COUNT(DISTINCT user_id) FROM events)                             AS active_users,
    (SELECT COUNT(*) FROM activation_events WHERE did_search = 1 AND did_booking = 1) AS activated_users,
    ROUND(100.0 * (SELECT COUNT(*) FROM activation_events WHERE did_search = 1 AND did_booking = 1)
          / (SELECT COUNT(*) FROM users), 2)                                 AS activation_rate_pct,
    (SELECT COUNT(DISTINCT user_id) FROM bookings)                           AS converted_users,
    ROUND(100.0 * (SELECT COUNT(DISTINCT user_id) FROM bookings)
          / (SELECT COUNT(*) FROM users), 2)                                 AS conversion_rate_pct,
    (SELECT ROUND(SUM(revenue), 2) FROM bookings)                            AS total_revenue_eur,
    (SELECT ROUND(SUM(revenue) / (SELECT COUNT(*) FROM users), 2) FROM bookings) AS arpu_eur,
    (SELECT ROUND(AVG(revenue), 2) FROM bookings)                            AS avg_booking_value_eur;
