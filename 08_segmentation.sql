-- =============================================================================
-- 08_segmentation.sql
-- Purpose : Cross-sectional user segmentation — country, platform, age group,
--           acquisition channel, and revenue-value tiers — for audience
--           slicing in a BI dashboard.
-- Tables  : users, events
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Segment summary by country: users, conversion rate, revenue, ARPU
-- -----------------------------------------------------------------------------
WITH user_revenue AS (
    SELECT user_id, SUM(revenue) AS lifetime_revenue
    FROM events
    WHERE event_name = 'booking_completed'
    GROUP BY user_id
)
SELECT
    u.country,
    COUNT(DISTINCT u.user_id)                                             AS users,
    COUNT(DISTINCT ur.user_id)                                            AS converted_users,
    ROUND(100.0 * COUNT(DISTINCT ur.user_id) / COUNT(DISTINCT u.user_id), 1) AS conversion_rate_pct,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0), 2)                       AS total_revenue_eur,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0) / COUNT(DISTINCT u.user_id), 2) AS arpu_eur
FROM users AS u
LEFT JOIN user_revenue AS ur ON ur.user_id = u.user_id
GROUP BY u.country
ORDER BY total_revenue_eur DESC;

-- -----------------------------------------------------------------------------
-- 2. Segment summary by platform
-- -----------------------------------------------------------------------------
WITH user_revenue AS (
    SELECT user_id, SUM(revenue) AS lifetime_revenue
    FROM events
    WHERE event_name = 'booking_completed'
    GROUP BY user_id
)
SELECT
    u.platform,
    COUNT(DISTINCT u.user_id)                                             AS users,
    COUNT(DISTINCT ur.user_id)                                            AS converted_users,
    ROUND(100.0 * COUNT(DISTINCT ur.user_id) / COUNT(DISTINCT u.user_id), 1) AS conversion_rate_pct,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0), 2)                       AS total_revenue_eur,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0) / COUNT(DISTINCT u.user_id), 2) AS arpu_eur
FROM users AS u
LEFT JOIN user_revenue AS ur ON ur.user_id = u.user_id
GROUP BY u.platform
ORDER BY total_revenue_eur DESC;

-- -----------------------------------------------------------------------------
-- 3. Segment summary by age group
-- -----------------------------------------------------------------------------
WITH user_revenue AS (
    SELECT user_id, SUM(revenue) AS lifetime_revenue
    FROM events
    WHERE event_name = 'booking_completed'
    GROUP BY user_id
)
SELECT
    COALESCE(u.age_group, 'Unspecified')                                  AS age_group,
    COUNT(DISTINCT u.user_id)                                             AS users,
    COUNT(DISTINCT ur.user_id)                                            AS converted_users,
    ROUND(100.0 * COUNT(DISTINCT ur.user_id) / COUNT(DISTINCT u.user_id), 1) AS conversion_rate_pct,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0), 2)                       AS total_revenue_eur,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0) / COUNT(DISTINCT u.user_id), 2) AS arpu_eur
FROM users AS u
LEFT JOIN user_revenue AS ur ON ur.user_id = u.user_id
GROUP BY COALESCE(u.age_group, 'Unspecified')
ORDER BY total_revenue_eur DESC;

-- -----------------------------------------------------------------------------
-- 4. Segment summary by acquisition channel
-- -----------------------------------------------------------------------------
WITH user_revenue AS (
    SELECT user_id, SUM(revenue) AS lifetime_revenue
    FROM events
    WHERE event_name = 'booking_completed'
    GROUP BY user_id
)
SELECT
    u.acquisition_channel,
    COUNT(DISTINCT u.user_id)                                             AS users,
    COUNT(DISTINCT ur.user_id)                                            AS converted_users,
    ROUND(100.0 * COUNT(DISTINCT ur.user_id) / COUNT(DISTINCT u.user_id), 1) AS conversion_rate_pct,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0), 2)                       AS total_revenue_eur,
    ROUND(COALESCE(SUM(ur.lifetime_revenue), 0) / COUNT(DISTINCT u.user_id), 2) AS arpu_eur
FROM users AS u
LEFT JOIN user_revenue AS ur ON ur.user_id = u.user_id
GROUP BY u.acquisition_channel
ORDER BY total_revenue_eur DESC;

-- -----------------------------------------------------------------------------
-- 5. Revenue segments (value tiers): bucket every user by lifetime revenue
--    into Non-payer / Low / Mid / High value using NTILE over payers, with
--    non-payers broken out separately
-- -----------------------------------------------------------------------------
WITH user_revenue AS (
    SELECT
        u.user_id,
        COALESCE(SUM(e.revenue), 0) AS lifetime_revenue
    FROM users AS u
    LEFT JOIN events AS e ON e.user_id = u.user_id AND e.event_name = 'booking_completed'
    GROUP BY u.user_id
),
payer_tiers AS (
    SELECT
        user_id,
        lifetime_revenue,
        NTILE(3) OVER (ORDER BY lifetime_revenue) AS value_tile
    FROM user_revenue
    WHERE lifetime_revenue > 0
),
segmented_users AS (
    SELECT
        ur.user_id,
        ur.lifetime_revenue,
        CASE
            WHEN ur.lifetime_revenue = 0 THEN 'Non-payer'
            WHEN pt.value_tile = 1       THEN 'Low value'
            WHEN pt.value_tile = 2       THEN 'Mid value'
            WHEN pt.value_tile = 3       THEN 'High value'
        END AS revenue_segment
    FROM user_revenue AS ur
    LEFT JOIN payer_tiers AS pt ON pt.user_id = ur.user_id
)
SELECT
    revenue_segment,
    COUNT(*)                                                       AS users,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM users), 1)      AS pct_of_users,
    ROUND(SUM(lifetime_revenue), 2)                                AS segment_revenue_eur,
    ROUND(100.0 * SUM(lifetime_revenue) /
          (SELECT SUM(revenue) FROM events WHERE event_name = 'booking_completed'), 1) AS pct_of_total_revenue,
    ROUND(AVG(lifetime_revenue), 2)                                AS avg_revenue_per_user_eur
FROM segmented_users
GROUP BY revenue_segment
ORDER BY avg_revenue_per_user_eur DESC;

-- -----------------------------------------------------------------------------
-- 6. Cross-tab: country x platform user distribution (audience matrix)
-- -----------------------------------------------------------------------------
SELECT
    country,
    SUM(CASE WHEN platform = 'iOS'     THEN 1 ELSE 0 END) AS ios_users,
    SUM(CASE WHEN platform = 'Android' THEN 1 ELSE 0 END) AS android_users,
    SUM(CASE WHEN platform = 'Web'     THEN 1 ELSE 0 END) AS web_users,
    COUNT(*)                                               AS total_users
FROM users
GROUP BY country
ORDER BY total_users DESC;
