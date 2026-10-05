-- =============================================================================
-- 10_business_recommendations.sql
-- Purpose : Management-ready rollup tables. Each query answers one business
--           question directly, in a form suitable for pasting into a slide
--           or BI tile. Written interpretation of these tables lives in
--           insights/phase2_summary.md.
-- Tables  : users, events, experiments
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Executive KPI summary — single row, top-line business health
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
    (SELECT COUNT(*) FROM users)                                                       AS total_users,
    ROUND(100.0 * (SELECT COUNT(*) FROM activation_events WHERE did_search = 1 AND did_booking = 1)
          / (SELECT COUNT(*) FROM users), 1)                                           AS activation_rate_pct,
    ROUND(100.0 * (SELECT COUNT(DISTINCT user_id) FROM bookings)
          / (SELECT COUNT(*) FROM users), 1)                                           AS conversion_rate_pct,
    (SELECT ROUND(SUM(revenue), 0) FROM bookings)                                      AS total_revenue_eur,
    (SELECT ROUND(SUM(revenue) / (SELECT COUNT(*) FROM users), 2) FROM bookings)       AS arpu_eur,
    (SELECT ROUND(100.0 * SUM(CASE WHEN julianday(
                (SELECT MAX(event_date) FROM events)) - julianday(last_event_date) >= 30
                THEN 1 ELSE 0 END) / COUNT(*), 1)
     FROM (SELECT user_id, MAX(event_date) AS last_event_date FROM events GROUP BY user_id)
    )                                                                                  AS churn_rate_pct;

-- -----------------------------------------------------------------------------
-- 2. Top revenue-driving segments: country x acquisition_channel, ranked
--    (where should marketing spend concentrate?)
-- -----------------------------------------------------------------------------
WITH user_revenue AS (
    SELECT user_id, SUM(revenue) AS lifetime_revenue
    FROM events
    WHERE event_name = 'booking_completed'
    GROUP BY user_id
)
SELECT
    u.country,
    u.acquisition_channel,
    COUNT(DISTINCT u.user_id)                                              AS users,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0), 2)                        AS revenue_eur,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0) / COUNT(DISTINCT u.user_id), 2) AS arpu_eur,
    RANK() OVER (ORDER BY COALESCE(SUM(ur.lifetime_revenue), 0) DESC)      AS revenue_rank
FROM users AS u
LEFT JOIN user_revenue AS ur ON ur.user_id = u.user_id
GROUP BY u.country, u.acquisition_channel
ORDER BY revenue_rank
LIMIT 10;

-- -----------------------------------------------------------------------------
-- 3. Underperforming acquisition channels: above-average signup volume but
--    below-average conversion — candidates for spend reallocation or
--    onboarding-flow fixes
-- -----------------------------------------------------------------------------
WITH channel_stats AS (
    SELECT
        u.acquisition_channel,
        COUNT(DISTINCT u.user_id)                                                       AS users,
        COUNT(DISTINCT CASE WHEN e.event_name = 'booking_completed' THEN e.user_id END)  AS converted_users,
        ROUND(100.0 * COUNT(DISTINCT CASE WHEN e.event_name = 'booking_completed' THEN e.user_id END)
              / COUNT(DISTINCT u.user_id), 1)                                            AS conversion_rate_pct
    FROM users AS u
    LEFT JOIN events AS e ON e.user_id = u.user_id
    GROUP BY u.acquisition_channel
),
overall AS (
    SELECT
        AVG(users)               AS avg_users,
        AVG(conversion_rate_pct) AS avg_conversion_rate_pct
    FROM channel_stats
)
SELECT
    cs.acquisition_channel,
    cs.users,
    cs.conversion_rate_pct,
    ROUND(o.avg_conversion_rate_pct, 1) AS overall_avg_conversion_rate_pct,
    ROUND(cs.conversion_rate_pct - o.avg_conversion_rate_pct, 1) AS gap_vs_average_pp
FROM channel_stats AS cs
CROSS JOIN overall AS o
WHERE cs.users >= o.avg_users
  AND cs.conversion_rate_pct < o.avg_conversion_rate_pct
ORDER BY gap_vs_average_pp ASC;

-- -----------------------------------------------------------------------------
-- 4. Feature adoption impact summary: adopters vs non-adopters, all three
--    engagement features side by side (supports a "invest in these features"
--    recommendation)
-- -----------------------------------------------------------------------------
WITH user_feature_flags AS (
    SELECT
        user_id,
        MAX(CASE WHEN event_name = 'booking_completed'        THEN 1 ELSE 0 END) AS converted,
        MAX(CASE WHEN event_name = 'notification_enabled'     THEN 1 ELSE 0 END) AS has_notification,
        MAX(CASE WHEN event_name = 'favourite_location_added' THEN 1 ELSE 0 END) AS has_favourite
    FROM events
    GROUP BY user_id
),
user_flags AS (
    SELECT
        u.user_id,
        COALESCE(f.converted, 0)        AS converted,
        COALESCE(f.has_notification, 0) AS has_notification,
        COALESCE(f.has_favourite, 0)    AS has_favourite
    FROM users AS u
    LEFT JOIN user_feature_flags AS f ON f.user_id = u.user_id
)
SELECT
    'notification_enabled'                                    AS feature,
    ROUND(100.0 * AVG(CASE WHEN has_notification = 1 THEN converted END), 1) AS adopter_conversion_pct,
    ROUND(100.0 * AVG(CASE WHEN has_notification = 0 THEN converted END), 1) AS non_adopter_conversion_pct,
    ROUND(100.0 * AVG(CASE WHEN has_notification = 1 THEN converted END)
        - 100.0 * AVG(CASE WHEN has_notification = 0 THEN converted END), 1) AS uplift_pp
FROM user_flags

UNION ALL

SELECT
    'favourite_location_added',
    ROUND(100.0 * AVG(CASE WHEN has_favourite = 1 THEN converted END), 1),
    ROUND(100.0 * AVG(CASE WHEN has_favourite = 0 THEN converted END), 1),
    ROUND(100.0 * AVG(CASE WHEN has_favourite = 1 THEN converted END)
        - 100.0 * AVG(CASE WHEN has_favourite = 0 THEN converted END), 1)
FROM user_flags;

-- -----------------------------------------------------------------------------
-- 5. Retention-risk segments: acquisition channels with Day 30 retention
--    below the company-wide average, sized by user volume (impact-weighted
--    priority list for retention investment)
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
        MAX(CASE WHEN a.days_since_signup = 30 THEN 1 ELSE 0 END) AS retained_day30
    FROM users AS u
    LEFT JOIN user_activity_days AS a ON a.user_id = u.user_id
    GROUP BY u.user_id, u.acquisition_channel
),
channel_retention AS (
    SELECT
        acquisition_channel,
        COUNT(*)                                        AS users,
        ROUND(100.0 * AVG(retained_day30), 1)            AS day30_retention_pct
    FROM retention_flags
    GROUP BY acquisition_channel
),
overall_retention AS (
    SELECT ROUND(100.0 * AVG(retained_day30), 1) AS overall_day30_retention_pct FROM retention_flags
)
SELECT
    cr.acquisition_channel,
    cr.users,
    cr.day30_retention_pct,
    o.overall_day30_retention_pct,
    ROUND(cr.day30_retention_pct - o.overall_day30_retention_pct, 1) AS gap_vs_average_pp
FROM channel_retention AS cr
CROSS JOIN overall_retention AS o
WHERE cr.day30_retention_pct < o.overall_day30_retention_pct
ORDER BY cr.users DESC;

-- -----------------------------------------------------------------------------
-- 6. Experiment rollout decision table: does the data support rolling out
--    simplified_booking_flow to 100% of users?
-- -----------------------------------------------------------------------------
WITH group_stats AS (
    SELECT
        experiment_group,
        COUNT(*)                        AS n,
        SUM(converted)                  AS conversions,
        1.0 * SUM(converted) / COUNT(*) AS conversion_rate
    FROM experiments
    GROUP BY experiment_group
),
pivoted AS (
    SELECT
        MAX(CASE WHEN experiment_group = 'control'   THEN n END)               AS n_c,
        MAX(CASE WHEN experiment_group = 'treatment' THEN n END)               AS n_t,
        MAX(CASE WHEN experiment_group = 'control'   THEN conversions END)     AS conv_c,
        MAX(CASE WHEN experiment_group = 'treatment' THEN conversions END)     AS conv_t,
        MAX(CASE WHEN experiment_group = 'control'   THEN conversion_rate END) AS p_c,
        MAX(CASE WHEN experiment_group = 'treatment' THEN conversion_rate END) AS p_t
    FROM group_stats
),
z AS (
    SELECT
        *,
        1.0 * (conv_c + conv_t) / (n_c + n_t) AS p_pooled
    FROM pivoted
)
SELECT
    ROUND(100.0 * p_c, 2) AS control_conversion_pct,
    ROUND(100.0 * p_t, 2) AS treatment_conversion_pct,
    ROUND(100.0 * (p_t - p_c), 2) AS absolute_uplift_pp,
    ROUND((p_t - p_c) / sqrt(p_pooled * (1 - p_pooled) * (1.0 / n_c + 1.0 / n_t)), 2) AS z_statistic,
    CASE
        WHEN (p_t - p_c) > 0
             AND ABS((p_t - p_c) / sqrt(p_pooled * (1 - p_pooled) * (1.0 / n_c + 1.0 / n_t))) >= 1.96
        THEN 'RECOMMEND ROLLOUT: uplift is positive and statistically significant at 95% CI'
        WHEN (p_t - p_c) > 0
        THEN 'DIRECTIONALLY POSITIVE: extend test duration to confirm significance'
        ELSE 'DO NOT ROLL OUT: no significant positive uplift observed'
    END AS recommendation
FROM z;
