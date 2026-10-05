-- =============================================================================
-- 04_funnel_analysis.sql
-- Purpose : Classic top-of-funnel to purchase funnel, cancellation rate, and
--           drop-off / abandonment analysis.
-- Funnel stages (distinct users reaching each stage, lifetime):
--   1. Signup            -> exists in users
--   2. Search Started     -> >=1 search_started event
--   3. Booking Started    -> >=1 booking_started event
--   4. Booking Completed  -> >=1 booking_completed event
-- Tables  : users, events
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Funnel stage counts (distinct users reaching each stage, any time)
-- -----------------------------------------------------------------------------
WITH stage_users AS (
    SELECT user_id, 1 AS reached_signup, 0 AS reached_search, 0 AS reached_booking_started, 0 AS reached_booking_completed
    FROM users

    UNION ALL

    SELECT user_id, 0, 1, 0, 0
    FROM events WHERE event_name = 'search_started'

    UNION ALL

    SELECT user_id, 0, 0, 1, 0
    FROM events WHERE event_name = 'booking_started'

    UNION ALL

    SELECT user_id, 0, 0, 0, 1
    FROM events WHERE event_name = 'booking_completed'
)
SELECT
    'signup'            AS funnel_stage, COUNT(DISTINCT user_id) AS users_reached FROM stage_users WHERE reached_signup = 1
UNION ALL
SELECT 'search_started',    COUNT(DISTINCT user_id) FROM stage_users WHERE reached_search = 1
UNION ALL
SELECT 'booking_started',   COUNT(DISTINCT user_id) FROM stage_users WHERE reached_booking_started = 1
UNION ALL
SELECT 'booking_completed', COUNT(DISTINCT user_id) FROM stage_users WHERE reached_booking_completed = 1;

-- -----------------------------------------------------------------------------
-- 2. Funnel with stage-over-stage conversion % and drop-off %, using window
--    functions (LAG) to compare each stage to the previous one
-- -----------------------------------------------------------------------------
WITH funnel_counts AS (
    SELECT 'signup' AS stage, 1 AS stage_order, COUNT(*) AS users_reached FROM users
    UNION ALL
    SELECT 'search_started', 2, COUNT(DISTINCT user_id) FROM events WHERE event_name = 'search_started'
    UNION ALL
    SELECT 'booking_started', 3, COUNT(DISTINCT user_id) FROM events WHERE event_name = 'booking_started'
    UNION ALL
    SELECT 'booking_completed', 4, COUNT(DISTINCT user_id) FROM events WHERE event_name = 'booking_completed'
),
funnel_with_lag AS (
    SELECT
        stage,
        stage_order,
        users_reached,
        LAG(users_reached) OVER (ORDER BY stage_order) AS prev_stage_users,
        FIRST_VALUE(users_reached) OVER (ORDER BY stage_order) AS top_of_funnel_users
    FROM funnel_counts
)
SELECT
    stage,
    users_reached,
    ROUND(100.0 * users_reached / top_of_funnel_users, 1)                                   AS pct_of_top_of_funnel,
    CASE WHEN prev_stage_users IS NULL THEN NULL
         ELSE ROUND(100.0 * users_reached / prev_stage_users, 1) END                        AS pct_of_previous_stage,
    CASE WHEN prev_stage_users IS NULL THEN NULL
         ELSE ROUND(100.0 * (prev_stage_users - users_reached) / prev_stage_users, 1) END   AS drop_off_pct_vs_previous
FROM funnel_with_lag
ORDER BY stage_order;

-- -----------------------------------------------------------------------------
-- 3. Cancellation rate: booking_cancelled as a share of all booking attempts
--    (booking_started), measured at the event (attempt) level
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE event_name = 'booking_started')    AS booking_attempts,
    COUNT(*) FILTER (WHERE event_name = 'booking_completed')  AS completed,
    COUNT(*) FILTER (WHERE event_name = 'booking_cancelled')  AS cancelled,
    COUNT(*) FILTER (WHERE event_name = 'payment_failed')     AS payment_failed,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE event_name = 'booking_cancelled')
        / COUNT(*) FILTER (WHERE event_name = 'booking_started'), 1
    ) AS cancellation_rate_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE event_name = 'booking_completed')
        / COUNT(*) FILTER (WHERE event_name = 'booking_started'), 1
    ) AS booking_completion_rate_pct
FROM events
WHERE event_name IN ('booking_started', 'booking_completed', 'booking_cancelled', 'payment_failed');

-- -----------------------------------------------------------------------------
-- 4. Top abandonment points: for sessions that started a search but never
--    completed a booking, what was the LAST event reached in that session?
--    (the furthest point of drop-off, using ROW_NUMBER over event_time)
-- -----------------------------------------------------------------------------
WITH search_sessions AS (
    SELECT DISTINCT session_id
    FROM events
    WHERE event_name = 'search_started'
),
non_converting_sessions AS (
    SELECT ss.session_id
    FROM search_sessions AS ss
    WHERE NOT EXISTS (
        SELECT 1 FROM events AS e2
        WHERE e2.session_id = ss.session_id AND e2.event_name = 'booking_completed'
    )
),
last_event_per_session AS (
    SELECT
        e.session_id,
        e.event_name,
        ROW_NUMBER() OVER (PARTITION BY e.session_id ORDER BY e.event_time DESC) AS rn
    FROM events AS e
    JOIN non_converting_sessions AS ncs ON e.session_id = ncs.session_id
)
SELECT
    event_name AS last_event_reached,
    COUNT(*)   AS session_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM non_converting_sessions), 1) AS pct_of_non_converting_sessions
FROM last_event_per_session
WHERE rn = 1
GROUP BY event_name
ORDER BY session_count DESC;

-- -----------------------------------------------------------------------------
-- 5. Funnel breakdown by acquisition channel (search -> booking_started ->
--    booking_completed conversion rates side by side)
-- -----------------------------------------------------------------------------
WITH channel_funnel AS (
    SELECT
        u.acquisition_channel,
        COUNT(DISTINCT u.user_id)                                                      AS signups,
        COUNT(DISTINCT CASE WHEN e.event_name = 'search_started'    THEN e.user_id END) AS searched,
        COUNT(DISTINCT CASE WHEN e.event_name = 'booking_started'   THEN e.user_id END) AS booking_started,
        COUNT(DISTINCT CASE WHEN e.event_name = 'booking_completed' THEN e.user_id END) AS booked
    FROM users AS u
    LEFT JOIN events AS e ON e.user_id = u.user_id
    GROUP BY u.acquisition_channel
)
SELECT
    acquisition_channel,
    signups,
    searched,
    booking_started,
    booked,
    ROUND(100.0 * searched / signups, 1)          AS search_rate_pct,
    ROUND(100.0 * booking_started / searched, 1)  AS booking_start_rate_pct,
    ROUND(100.0 * booked / booking_started, 1)    AS booking_completion_rate_pct,
    ROUND(100.0 * booked / signups, 1)            AS overall_conversion_pct
FROM channel_funnel
ORDER BY overall_conversion_pct DESC;
