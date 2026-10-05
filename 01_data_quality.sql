-- =============================================================================
-- 01_data_quality.sql
-- Purpose : SQL-side data quality checks, complementing src/validate_data.py.
--           These are the checks a Product Analyst would run before trusting
--           any downstream KPI, funnel, retention, or experiment number.
-- Tables  : users, events, experiments
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Row counts per table
-- -----------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM users)       AS users_row_count,
    (SELECT COUNT(*) FROM events)      AS events_row_count,
    (SELECT COUNT(*) FROM experiments) AS experiments_row_count;

-- -----------------------------------------------------------------------------
-- 2. Duplicate primary key check (should return zero rows)
-- -----------------------------------------------------------------------------
SELECT 'users.user_id' AS key_checked, user_id AS duplicate_value, COUNT(*) AS occurrences
FROM users
GROUP BY user_id
HAVING COUNT(*) > 1

UNION ALL

SELECT 'events.event_id', event_id, COUNT(*)
FROM events
GROUP BY event_id
HAVING COUNT(*) > 1;

-- -----------------------------------------------------------------------------
-- 3. Orphan foreign keys: events/experiments referencing a user_id that
--    does not exist in users (should return zero rows)
-- -----------------------------------------------------------------------------
SELECT 'events' AS source_table, e.user_id AS orphan_user_id, COUNT(*) AS row_count
FROM events AS e
LEFT JOIN users AS u ON e.user_id = u.user_id
WHERE u.user_id IS NULL
GROUP BY e.user_id

UNION ALL

SELECT 'experiments', x.user_id, COUNT(*)
FROM experiments AS x
LEFT JOIN users AS u ON x.user_id = u.user_id
WHERE u.user_id IS NULL
GROUP BY x.user_id;

-- -----------------------------------------------------------------------------
-- 4. Events occurring before the user's signup_date (should return zero rows)
-- -----------------------------------------------------------------------------
SELECT
    e.event_id,
    e.user_id,
    e.event_date,
    u.signup_date
FROM events AS e
JOIN users AS u ON e.user_id = u.user_id
WHERE date(e.event_date) < date(u.signup_date);

-- -----------------------------------------------------------------------------
-- 5. Revenue integrity: negative revenue, or revenue on a non-completed
--    booking event (both should return zero rows)
-- -----------------------------------------------------------------------------
SELECT 'negative_revenue' AS issue, COUNT(*) AS row_count
FROM events
WHERE revenue < 0

UNION ALL

SELECT 'revenue_on_non_completed_booking', COUNT(*)
FROM events
WHERE revenue IS NOT NULL
  AND revenue > 0
  AND event_name <> 'booking_completed'

UNION ALL

SELECT 'completed_booking_missing_revenue', COUNT(*)
FROM events
WHERE event_name = 'booking_completed'
  AND (revenue IS NULL OR revenue <= 0);

-- -----------------------------------------------------------------------------
-- 6. Null-rate profile for every column that is allowed to contain nulls
-- -----------------------------------------------------------------------------
SELECT
    'users.age_group' AS column_checked,
    ROUND(100.0 * SUM(CASE WHEN age_group IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_rate_pct
FROM users

UNION ALL

SELECT
    'events.revenue',
    ROUND(100.0 * SUM(CASE WHEN revenue IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM events

UNION ALL

SELECT
    'events.ride_distance_km',
    ROUND(100.0 * SUM(CASE WHEN ride_distance_km IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM events

UNION ALL

SELECT
    'events.payment_method',
    ROUND(100.0 * SUM(CASE WHEN payment_method IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM events;

-- -----------------------------------------------------------------------------
-- 7. Categorical domain check: values outside the expected value set
--    (should return zero rows for each table)
-- -----------------------------------------------------------------------------
SELECT 'users.country' AS column_checked, country AS invalid_value, COUNT(*) AS row_count
FROM users
WHERE country NOT IN ('Germany', 'Austria', 'Spain', 'Netherlands', 'France')
GROUP BY country

UNION ALL

SELECT 'users.platform', platform, COUNT(*)
FROM users
WHERE platform NOT IN ('iOS', 'Android', 'Web')
GROUP BY platform

UNION ALL

SELECT 'users.experiment_group', experiment_group, COUNT(*)
FROM users
WHERE experiment_group NOT IN ('control', 'treatment')
GROUP BY experiment_group

UNION ALL

SELECT 'events.event_name', event_name, COUNT(*)
FROM events
WHERE event_name NOT IN (
    'app_open', 'signup_completed', 'location_permission_granted', 'search_started',
    'search_completed', 'ride_option_viewed', 'promo_viewed', 'booking_started',
    'booking_completed', 'booking_cancelled', 'favourite_location_added',
    'notification_enabled', 'support_contacted', 'payment_failed', 'rating_submitted'
)
GROUP BY event_name;

-- -----------------------------------------------------------------------------
-- 8. Experiment-group consistency: experiments.experiment_group must match
--    the user's assigned group in users.experiment_group (should be zero rows)
-- -----------------------------------------------------------------------------
SELECT
    x.user_id,
    x.experiment_group AS experiments_group,
    u.experiment_group AS users_group
FROM experiments AS x
JOIN users AS u ON x.user_id = u.user_id
WHERE x.experiment_group <> u.experiment_group;

-- -----------------------------------------------------------------------------
-- 9. Date range validity: min/max signup and event dates, and overall span
-- -----------------------------------------------------------------------------
SELECT
    MIN(signup_date) AS earliest_signup,
    MAX(signup_date) AS latest_signup,
    CAST(julianday(MAX(signup_date)) - julianday(MIN(signup_date)) AS INTEGER) AS signup_span_days
FROM users;

SELECT
    MIN(event_date) AS earliest_event,
    MAX(event_date) AS latest_event,
    CAST(julianday(MAX(event_date)) - julianday(MIN(event_date)) AS INTEGER) AS event_span_days
FROM events;

-- -----------------------------------------------------------------------------
-- 10. Funnel logic sanity check: sessions where booking_completed appears
--     without a booking_started, or booking_started without a search_started
--     in the same session (both should return zero rows)
-- -----------------------------------------------------------------------------
WITH session_flags AS (
    SELECT
        session_id,
        MAX(CASE WHEN event_name = 'search_started'    THEN 1 ELSE 0 END) AS has_search_started,
        MAX(CASE WHEN event_name = 'booking_started'    THEN 1 ELSE 0 END) AS has_booking_started,
        MAX(CASE WHEN event_name = 'booking_completed'  THEN 1 ELSE 0 END) AS has_booking_completed
    FROM events
    GROUP BY session_id
)
SELECT
    'booking_completed_without_booking_started' AS issue,
    COUNT(*) AS session_count
FROM session_flags
WHERE has_booking_completed = 1 AND has_booking_started = 0

UNION ALL

SELECT
    'booking_started_without_search_started',
    COUNT(*)
FROM session_flags
WHERE has_booking_started = 1 AND has_search_started = 0;
