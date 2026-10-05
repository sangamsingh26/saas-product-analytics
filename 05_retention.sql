-- =============================================================================
-- 05_retention.sql
-- Purpose : Day 1 / Day 7 / Day 30 retention, overall and by segment.
-- Definition: a user is "retained on day N" if they have >=1 event on the
--             calendar date exactly N days after their signup_date.
-- Tables  : users, events
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Overall Day 1 / Day 7 / Day 30 retention rate
-- -----------------------------------------------------------------------------
WITH user_activity_days AS (
    SELECT DISTINCT
        e.user_id,
        CAST(julianday(e.event_date) - julianday(u.signup_date) AS INTEGER) AS days_since_signup
    FROM events AS e
    JOIN users AS u ON e.user_id = u.user_id
),
retention_flags AS (
    SELECT
        u.user_id,
        MAX(CASE WHEN a.days_since_signup = 1  THEN 1 ELSE 0 END)  AS retained_day1,
        MAX(CASE WHEN a.days_since_signup = 7  THEN 1 ELSE 0 END)  AS retained_day7,
        MAX(CASE WHEN a.days_since_signup = 30 THEN 1 ELSE 0 END)  AS retained_day30
    FROM users AS u
    LEFT JOIN user_activity_days AS a ON a.user_id = u.user_id
    GROUP BY u.user_id
)
SELECT
    COUNT(*)                                            AS total_users,
    SUM(retained_day1)                                  AS day1_retained_users,
    ROUND(100.0 * SUM(retained_day1) / COUNT(*), 1)      AS day1_retention_pct,
    SUM(retained_day7)                                  AS day7_retained_users,
    ROUND(100.0 * SUM(retained_day7) / COUNT(*), 1)      AS day7_retention_pct,
    SUM(retained_day30)                                 AS day30_retained_users,
    ROUND(100.0 * SUM(retained_day30) / COUNT(*), 1)     AS day30_retention_pct
FROM retention_flags;

-- -----------------------------------------------------------------------------
-- 2. Retention by country
-- -----------------------------------------------------------------------------
WITH user_activity_days AS (
    SELECT DISTINCT
        e.user_id,
        CAST(julianday(e.event_date) - julianday(u.signup_date) AS INTEGER) AS days_since_signup
    FROM events AS e
    JOIN users AS u ON e.user_id = u.user_id
),
retention_flags AS (
    SELECT
        u.user_id,
        u.country,
        MAX(CASE WHEN a.days_since_signup = 1  THEN 1 ELSE 0 END) AS retained_day1,
        MAX(CASE WHEN a.days_since_signup = 7  THEN 1 ELSE 0 END) AS retained_day7,
        MAX(CASE WHEN a.days_since_signup = 30 THEN 1 ELSE 0 END) AS retained_day30
    FROM users AS u
    LEFT JOIN user_activity_days AS a ON a.user_id = u.user_id
    GROUP BY u.user_id, u.country
)
SELECT
    country,
    COUNT(*)                                        AS total_users,
    ROUND(100.0 * SUM(retained_day1) / COUNT(*), 1)  AS day1_retention_pct,
    ROUND(100.0 * SUM(retained_day7) / COUNT(*), 1)  AS day7_retention_pct,
    ROUND(100.0 * SUM(retained_day30) / COUNT(*), 1) AS day30_retention_pct
FROM retention_flags
GROUP BY country
ORDER BY day30_retention_pct DESC;

-- -----------------------------------------------------------------------------
-- 3. Retention by platform
-- -----------------------------------------------------------------------------
WITH user_activity_days AS (
    SELECT DISTINCT
        e.user_id,
        CAST(julianday(e.event_date) - julianday(u.signup_date) AS INTEGER) AS days_since_signup
    FROM events AS e
    JOIN users AS u ON e.user_id = u.user_id
),
retention_flags AS (
    SELECT
        u.user_id,
        u.platform,
        MAX(CASE WHEN a.days_since_signup = 1  THEN 1 ELSE 0 END) AS retained_day1,
        MAX(CASE WHEN a.days_since_signup = 7  THEN 1 ELSE 0 END) AS retained_day7,
        MAX(CASE WHEN a.days_since_signup = 30 THEN 1 ELSE 0 END) AS retained_day30
    FROM users AS u
    LEFT JOIN user_activity_days AS a ON a.user_id = u.user_id
    GROUP BY u.user_id, u.platform
)
SELECT
    platform,
    COUNT(*)                                        AS total_users,
    ROUND(100.0 * SUM(retained_day1) / COUNT(*), 1)  AS day1_retention_pct,
    ROUND(100.0 * SUM(retained_day7) / COUNT(*), 1)  AS day7_retention_pct,
    ROUND(100.0 * SUM(retained_day30) / COUNT(*), 1) AS day30_retention_pct
FROM retention_flags
GROUP BY platform
ORDER BY day30_retention_pct DESC;

-- -----------------------------------------------------------------------------
-- 4. Retention by acquisition channel
-- -----------------------------------------------------------------------------
WITH user_activity_days AS (
    SELECT DISTINCT
        e.user_id,
        CAST(julianday(e.event_date) - julianday(u.signup_date) AS INTEGER) AS days_since_signup
    FROM events AS e
    JOIN users AS u ON e.user_id = u.user_id
),
retention_flags AS (
    SELECT
        u.user_id,
        u.acquisition_channel,
        MAX(CASE WHEN a.days_since_signup = 1  THEN 1 ELSE 0 END) AS retained_day1,
        MAX(CASE WHEN a.days_since_signup = 7  THEN 1 ELSE 0 END) AS retained_day7,
        MAX(CASE WHEN a.days_since_signup = 30 THEN 1 ELSE 0 END) AS retained_day30
    FROM users AS u
    LEFT JOIN user_activity_days AS a ON a.user_id = u.user_id
    GROUP BY u.user_id, u.acquisition_channel
)
SELECT
    acquisition_channel,
    COUNT(*)                                        AS total_users,
    ROUND(100.0 * SUM(retained_day1) / COUNT(*), 1)  AS day1_retention_pct,
    ROUND(100.0 * SUM(retained_day7) / COUNT(*), 1)  AS day7_retention_pct,
    ROUND(100.0 * SUM(retained_day30) / COUNT(*), 1) AS day30_retention_pct
FROM retention_flags
GROUP BY acquisition_channel
ORDER BY day30_retention_pct DESC;

-- -----------------------------------------------------------------------------
-- 5. Churn: users with no activity for >=30 consecutive days after their
--    last recorded event, measured against the dataset's last known date
-- -----------------------------------------------------------------------------
WITH last_activity AS (
    SELECT
        u.user_id,
        u.signup_date,
        MAX(e.event_date) AS last_event_date
    FROM users AS u
    LEFT JOIN events AS e ON e.user_id = u.user_id
    GROUP BY u.user_id, u.signup_date
),
dataset_bounds AS (
    SELECT MAX(event_date) AS dataset_last_date FROM events
)
SELECT
    COUNT(*)                                                                      AS total_users,
    SUM(CASE WHEN julianday(db.dataset_last_date) - julianday(la.last_event_date) >= 30
              THEN 1 ELSE 0 END)                                                  AS churned_users,
    ROUND(100.0 * SUM(CASE WHEN julianday(db.dataset_last_date) - julianday(la.last_event_date) >= 30
                            THEN 1 ELSE 0 END) / COUNT(*), 1)                     AS churn_rate_pct
FROM last_activity AS la
CROSS JOIN dataset_bounds AS db;
