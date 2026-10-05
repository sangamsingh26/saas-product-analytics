-- =============================================================================
-- 07_feature_adoption.sql
-- Purpose : Adoption rate of key engagement features, and whether adopting
--           them is associated with higher retention and conversion.
-- Features analysed: notification_enabled, favourite_location_added,
--                     promo_viewed.
-- Note: this is an observational, correlational comparison (adopters vs
--       non-adopters), not a causal/randomised estimate — see caveats in
--       insights/phase2_summary.md.
-- Performance note: per-user feature flags are computed with a single
--       GROUP BY pass over events (conditional MAX aggregation) rather than
--       correlated EXISTS subqueries per user, which is both faster and the
--       more idiomatic SQL pattern for this kind of user-level flagging.
-- Tables  : users, events
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Adoption rate of each feature (% of users who ever triggered it)
-- -----------------------------------------------------------------------------
SELECT
    'notification_enabled' AS feature,
    COUNT(DISTINCT user_id)                                                    AS adopters,
    ROUND(100.0 * COUNT(DISTINCT user_id) / (SELECT COUNT(*) FROM users), 1)   AS adoption_rate_pct
FROM events WHERE event_name = 'notification_enabled'

UNION ALL

SELECT
    'favourite_location_added',
    COUNT(DISTINCT user_id),
    ROUND(100.0 * COUNT(DISTINCT user_id) / (SELECT COUNT(*) FROM users), 1)
FROM events WHERE event_name = 'favourite_location_added'

UNION ALL

SELECT
    'promo_viewed',
    COUNT(DISTINCT user_id),
    ROUND(100.0 * COUNT(DISTINCT user_id) / (SELECT COUNT(*) FROM users), 1)
FROM events WHERE event_name = 'promo_viewed';

-- -----------------------------------------------------------------------------
-- 2. Feature adoption vs Day 7 / Day 30 retention and conversion
--    (adopters vs non-adopters, per feature)
-- -----------------------------------------------------------------------------
WITH user_feature_flags AS (
    SELECT
        user_id,
        MAX(CASE WHEN event_name = 'booking_completed'          THEN 1 ELSE 0 END) AS converted,
        MAX(CASE WHEN event_name = 'notification_enabled'       THEN 1 ELSE 0 END) AS has_notification,
        MAX(CASE WHEN event_name = 'favourite_location_added'   THEN 1 ELSE 0 END) AS has_favourite,
        MAX(CASE WHEN event_name = 'promo_viewed'                THEN 1 ELSE 0 END) AS has_promo_view
    FROM events
    GROUP BY user_id
),
user_retention_flags AS (
    SELECT
        e.user_id,
        MAX(CASE WHEN julianday(e.event_date) - julianday(u.signup_date) = 7  THEN 1 ELSE 0 END) AS retained_day7,
        MAX(CASE WHEN julianday(e.event_date) - julianday(u.signup_date) = 30 THEN 1 ELSE 0 END) AS retained_day30
    FROM events AS e
    JOIN users AS u ON e.user_id = u.user_id
    GROUP BY e.user_id
),
user_flags AS (
    SELECT
        u.user_id,
        COALESCE(r.retained_day7, 0)  AS retained_day7,
        COALESCE(r.retained_day30, 0) AS retained_day30,
        COALESCE(f.converted, 0)         AS converted,
        COALESCE(f.has_notification, 0)  AS has_notification,
        COALESCE(f.has_favourite, 0)     AS has_favourite,
        COALESCE(f.has_promo_view, 0)    AS has_promo_view
    FROM users AS u
    LEFT JOIN user_feature_flags AS f ON f.user_id = u.user_id
    LEFT JOIN user_retention_flags AS r ON r.user_id = u.user_id
)
SELECT
    'notification_enabled'                                                  AS feature,
    CASE WHEN has_notification = 1 THEN 'Adopters' ELSE 'Non-adopters' END  AS segment,
    COUNT(*)                                                                AS users,
    ROUND(100.0 * AVG(retained_day7), 1)                                    AS day7_retention_pct,
    ROUND(100.0 * AVG(retained_day30), 1)                                   AS day30_retention_pct,
    ROUND(100.0 * AVG(converted), 1)                                        AS conversion_rate_pct
FROM user_flags
GROUP BY has_notification

UNION ALL

SELECT
    'favourite_location_added',
    CASE WHEN has_favourite = 1 THEN 'Adopters' ELSE 'Non-adopters' END,
    COUNT(*),
    ROUND(100.0 * AVG(retained_day7), 1),
    ROUND(100.0 * AVG(retained_day30), 1),
    ROUND(100.0 * AVG(converted), 1)
FROM user_flags
GROUP BY has_favourite

UNION ALL

SELECT
    'promo_viewed',
    CASE WHEN has_promo_view = 1 THEN 'Adopters' ELSE 'Non-adopters' END,
    COUNT(*),
    ROUND(100.0 * AVG(retained_day7), 1),
    ROUND(100.0 * AVG(retained_day30), 1),
    ROUND(100.0 * AVG(converted), 1)
FROM user_flags
GROUP BY has_promo_view
ORDER BY feature, segment;

-- -----------------------------------------------------------------------------
-- 3. Feature adoption by platform (which platforms adopt features most?)
-- -----------------------------------------------------------------------------
WITH user_feature_flags AS (
    SELECT
        user_id,
        MAX(CASE WHEN event_name = 'notification_enabled'     THEN 1 ELSE 0 END) AS has_notification,
        MAX(CASE WHEN event_name = 'favourite_location_added' THEN 1 ELSE 0 END) AS has_favourite,
        MAX(CASE WHEN event_name = 'promo_viewed'              THEN 1 ELSE 0 END) AS has_promo_view
    FROM events
    GROUP BY user_id
)
SELECT
    u.platform,
    COUNT(*)                                                            AS total_users,
    ROUND(100.0 * AVG(COALESCE(f.has_notification, 0)), 1)              AS notification_adoption_pct,
    ROUND(100.0 * AVG(COALESCE(f.has_favourite, 0)), 1)                 AS favourite_adoption_pct,
    ROUND(100.0 * AVG(COALESCE(f.has_promo_view, 0)), 1)                AS promo_view_adoption_pct
FROM users AS u
LEFT JOIN user_feature_flags AS f ON f.user_id = u.user_id
GROUP BY u.platform
ORDER BY u.platform;

-- -----------------------------------------------------------------------------
-- 4. Users adopting multiple "sticky" features vs none — does stacking
--    features compound the retention effect?
-- -----------------------------------------------------------------------------
WITH user_feature_flags AS (
    SELECT
        user_id,
        MAX(CASE WHEN event_name = 'notification_enabled'     THEN 1 ELSE 0 END) AS has_notification,
        MAX(CASE WHEN event_name = 'favourite_location_added' THEN 1 ELSE 0 END) AS has_favourite,
        MAX(CASE WHEN event_name = 'promo_viewed'              THEN 1 ELSE 0 END) AS has_promo_view
    FROM events
    GROUP BY user_id
),
user_retention_flags AS (
    SELECT
        e.user_id,
        MAX(CASE WHEN julianday(e.event_date) - julianday(u.signup_date) = 30 THEN 1 ELSE 0 END) AS retained_day30
    FROM events AS e
    JOIN users AS u ON e.user_id = u.user_id
    GROUP BY e.user_id
),
feature_counts AS (
    SELECT
        u.user_id,
        COALESCE(f.has_notification, 0) + COALESCE(f.has_favourite, 0) + COALESCE(f.has_promo_view, 0) AS features_adopted
    FROM users AS u
    LEFT JOIN user_feature_flags AS f ON f.user_id = u.user_id
)
SELECT
    fc.features_adopted,
    COUNT(*)                                            AS users,
    ROUND(100.0 * AVG(COALESCE(r.retained_day30, 0)), 1) AS day30_retention_pct
FROM feature_counts AS fc
LEFT JOIN user_retention_flags AS r ON r.user_id = fc.user_id
GROUP BY fc.features_adopted
ORDER BY fc.features_adopted;
