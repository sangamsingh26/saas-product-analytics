-- =============================================================================
-- 02_business_overview.sql
-- Purpose : A high-level "at a glance" snapshot of the business, the kind of
--           output a Product/BI Analyst would open a stakeholder meeting with.
-- Tables  : users, events, experiments
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Headline snapshot: users, bookings, revenue, and the date range covered
-- -----------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM users)                                              AS total_users,
    (SELECT COUNT(*) FROM events WHERE event_name = 'booking_completed')      AS total_bookings,
    (SELECT ROUND(SUM(revenue), 2) FROM events WHERE event_name = 'booking_completed') AS total_revenue_eur,
    (SELECT MIN(signup_date) FROM users)                                      AS first_signup,
    (SELECT MAX(signup_date) FROM users)                                      AS last_signup,
    (SELECT MIN(event_date) FROM events)                                      AS first_event,
    (SELECT MAX(event_date) FROM events)                                      AS last_event;

-- -----------------------------------------------------------------------------
-- 2. User base composition by country (share of total users)
-- -----------------------------------------------------------------------------
SELECT
    country,
    COUNT(*)                                                     AS user_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM users), 1)    AS pct_of_users
FROM users
GROUP BY country
ORDER BY user_count DESC;

-- -----------------------------------------------------------------------------
-- 3. User base composition by platform
-- -----------------------------------------------------------------------------
SELECT
    platform,
    COUNT(*)                                                  AS user_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM users), 1) AS pct_of_users
FROM users
GROUP BY platform
ORDER BY user_count DESC;

-- -----------------------------------------------------------------------------
-- 4. User base composition by acquisition channel
-- -----------------------------------------------------------------------------
SELECT
    acquisition_channel,
    COUNT(*)                                                  AS user_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM users), 1) AS pct_of_users
FROM users
GROUP BY acquisition_channel
ORDER BY user_count DESC;

-- -----------------------------------------------------------------------------
-- 5. User base composition by age group (nulls shown as 'Unspecified')
-- -----------------------------------------------------------------------------
SELECT
    COALESCE(age_group, 'Unspecified')                        AS age_group,
    COUNT(*)                                                  AS user_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM users), 1) AS pct_of_users
FROM users
GROUP BY COALESCE(age_group, 'Unspecified')
ORDER BY user_count DESC;

-- -----------------------------------------------------------------------------
-- 6. Monthly signup trend
-- -----------------------------------------------------------------------------
SELECT
    strftime('%Y-%m', signup_date) AS signup_month,
    COUNT(*)                       AS new_users
FROM users
GROUP BY signup_month
ORDER BY signup_month;

-- -----------------------------------------------------------------------------
-- 7. Monthly revenue and booking trend
-- -----------------------------------------------------------------------------
SELECT
    strftime('%Y-%m', event_date)  AS month,
    COUNT(*)                       AS completed_bookings,
    ROUND(SUM(revenue), 2)         AS revenue_eur,
    ROUND(AVG(revenue), 2)         AS avg_booking_value_eur
FROM events
WHERE event_name = 'booking_completed'
GROUP BY month
ORDER BY month;

-- -----------------------------------------------------------------------------
-- 8. Event volume by product area (where is engagement concentrated?)
-- -----------------------------------------------------------------------------
SELECT
    product_area,
    COUNT(*)                                                    AS event_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM events), 1)  AS pct_of_events
FROM events
GROUP BY product_area
ORDER BY event_count DESC;
