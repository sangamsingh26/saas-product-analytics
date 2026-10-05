-- =============================================================================
-- 09_ab_testing.sql
-- Purpose : Evaluate the `simplified_booking_flow` experiment — control vs
--           treatment sample sizes, conversion uplift, revenue uplift, and
--           statistical-significance building blocks (two-proportion z-test,
--           two-sample mean comparison) computed directly in SQL.
-- Note: SQLite has no built-in normal-CDF function, so exact p-values are
--       not computed here. Instead we compute the z-statistic and compare
--       it against standard critical values (1.645 / 1.96 / 2.576 for
--       90% / 95% / 99% two-tailed confidence) — the same threshold check
--       a p-value comparison against 0.10 / 0.05 / 0.01 would produce.
-- Tables  : experiments, events, users
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Sample sizes and raw conversion counts by group
-- -----------------------------------------------------------------------------
SELECT
    experiment_group,
    COUNT(*)                          AS users,
    SUM(converted)                    AS converted_users,
    ROUND(100.0 * SUM(converted) / COUNT(*), 2) AS conversion_rate_pct
FROM experiments
GROUP BY experiment_group
ORDER BY experiment_group;

-- -----------------------------------------------------------------------------
-- 2. Conversion uplift: treatment vs control (absolute pp and relative %)
-- -----------------------------------------------------------------------------
WITH group_stats AS (
    SELECT
        experiment_group,
        COUNT(*)                              AS n,
        SUM(converted)                        AS conversions,
        1.0 * SUM(converted) / COUNT(*)       AS conversion_rate
    FROM experiments
    GROUP BY experiment_group
),
pivoted AS (
    SELECT
        MAX(CASE WHEN experiment_group = 'control'   THEN conversion_rate END) AS control_rate,
        MAX(CASE WHEN experiment_group = 'treatment' THEN conversion_rate END) AS treatment_rate,
        MAX(CASE WHEN experiment_group = 'control'   THEN n END)               AS control_n,
        MAX(CASE WHEN experiment_group = 'treatment' THEN n END)               AS treatment_n
    FROM group_stats
)
SELECT
    ROUND(100.0 * control_rate, 2)                                     AS control_conversion_pct,
    ROUND(100.0 * treatment_rate, 2)                                   AS treatment_conversion_pct,
    ROUND(100.0 * (treatment_rate - control_rate), 2)                  AS absolute_uplift_pp,
    ROUND(100.0 * (treatment_rate - control_rate) / control_rate, 1)   AS relative_uplift_pct,
    control_n,
    treatment_n
FROM pivoted;

-- -----------------------------------------------------------------------------
-- 3. Revenue per user (ARPU) by group and uplift
-- -----------------------------------------------------------------------------
WITH user_revenue AS (
    SELECT
        x.user_id,
        x.experiment_group,
        COALESCE(SUM(e.revenue), 0) AS lifetime_revenue
    FROM experiments AS x
    LEFT JOIN events AS e ON e.user_id = x.user_id AND e.event_name = 'booking_completed'
    GROUP BY x.user_id, x.experiment_group
),
group_arpu AS (
    SELECT
        experiment_group,
        COUNT(*)                  AS n,
        ROUND(SUM(lifetime_revenue), 2)         AS total_revenue_eur,
        ROUND(AVG(lifetime_revenue), 2)         AS arpu_eur
    FROM user_revenue
    GROUP BY experiment_group
)
SELECT
    *,
    ROUND(
        100.0 * (arpu_eur - (SELECT arpu_eur FROM group_arpu WHERE experiment_group = 'control'))
        / (SELECT arpu_eur FROM group_arpu WHERE experiment_group = 'control'), 1
    ) AS arpu_uplift_vs_control_pct
FROM group_arpu
ORDER BY experiment_group;

-- -----------------------------------------------------------------------------
-- 4. Statistical significance — two-proportion z-test on conversion rate
-- -----------------------------------------------------------------------------
WITH group_stats AS (
    SELECT
        experiment_group,
        COUNT(*)                        AS n,
        SUM(converted)                  AS conversions
    FROM experiments
    GROUP BY experiment_group
),
pivoted AS (
    SELECT
        MAX(CASE WHEN experiment_group = 'control'   THEN n END)           AS n_c,
        MAX(CASE WHEN experiment_group = 'treatment' THEN n END)           AS n_t,
        MAX(CASE WHEN experiment_group = 'control'   THEN conversions END) AS conv_c,
        MAX(CASE WHEN experiment_group = 'treatment' THEN conversions END) AS conv_t
    FROM group_stats
),
calc AS (
    SELECT
        n_c, n_t, conv_c, conv_t,
        1.0 * conv_c / n_c                                   AS p_c,
        1.0 * conv_t / n_t                                   AS p_t,
        1.0 * (conv_c + conv_t) / (n_c + n_t)                AS p_pooled
    FROM pivoted
)
SELECT
    ROUND(100.0 * p_c, 2)                                                       AS control_rate_pct,
    ROUND(100.0 * p_t, 2)                                                       AS treatment_rate_pct,
    ROUND(100.0 * (p_t - p_c), 2)                                               AS absolute_uplift_pp,
    ROUND(
        (p_t - p_c) / sqrt(p_pooled * (1 - p_pooled) * (1.0 / n_c + 1.0 / n_t)), 3
    )                                                                            AS z_statistic,
    CASE
        WHEN ABS((p_t - p_c) / sqrt(p_pooled * (1 - p_pooled) * (1.0 / n_c + 1.0 / n_t))) >= 2.576 THEN 'Significant at 99% CI'
        WHEN ABS((p_t - p_c) / sqrt(p_pooled * (1 - p_pooled) * (1.0 / n_c + 1.0 / n_t))) >= 1.96  THEN 'Significant at 95% CI'
        WHEN ABS((p_t - p_c) / sqrt(p_pooled * (1 - p_pooled) * (1.0 / n_c + 1.0 / n_t))) >= 1.645 THEN 'Significant at 90% CI'
        ELSE 'Not statistically significant'
    END                                                                          AS significance_verdict
FROM calc;

-- -----------------------------------------------------------------------------
-- 5. Statistical significance — two-sample z-test on revenue per user (ARPU)
--    using population variance per group (large-sample normal approximation)
-- -----------------------------------------------------------------------------
WITH user_revenue AS (
    SELECT
        x.user_id,
        x.experiment_group,
        COALESCE(SUM(e.revenue), 0) AS lifetime_revenue
    FROM experiments AS x
    LEFT JOIN events AS e ON e.user_id = x.user_id AND e.event_name = 'booking_completed'
    GROUP BY x.user_id, x.experiment_group
),
group_moments AS (
    SELECT
        experiment_group,
        COUNT(*)                                                             AS n,
        AVG(lifetime_revenue)                                                AS mean_revenue,
        AVG(lifetime_revenue * lifetime_revenue) - AVG(lifetime_revenue) * AVG(lifetime_revenue) AS variance_revenue
    FROM user_revenue
    GROUP BY experiment_group
),
pivoted AS (
    SELECT
        MAX(CASE WHEN experiment_group = 'control'   THEN n END)              AS n_c,
        MAX(CASE WHEN experiment_group = 'treatment' THEN n END)              AS n_t,
        MAX(CASE WHEN experiment_group = 'control'   THEN mean_revenue END)   AS mean_c,
        MAX(CASE WHEN experiment_group = 'treatment' THEN mean_revenue END)   AS mean_t,
        MAX(CASE WHEN experiment_group = 'control'   THEN variance_revenue END) AS var_c,
        MAX(CASE WHEN experiment_group = 'treatment' THEN variance_revenue END) AS var_t
    FROM group_moments
)
SELECT
    ROUND(mean_c, 2)  AS control_arpu_eur,
    ROUND(mean_t, 2)  AS treatment_arpu_eur,
    ROUND(mean_t - mean_c, 2) AS absolute_uplift_eur,
    ROUND((mean_t - mean_c) / sqrt(var_c / n_c + var_t / n_t), 3) AS z_statistic,
    CASE
        WHEN ABS((mean_t - mean_c) / sqrt(var_c / n_c + var_t / n_t)) >= 2.576 THEN 'Significant at 99% CI'
        WHEN ABS((mean_t - mean_c) / sqrt(var_c / n_c + var_t / n_t)) >= 1.96  THEN 'Significant at 95% CI'
        WHEN ABS((mean_t - mean_c) / sqrt(var_c / n_c + var_t / n_t)) >= 1.645 THEN 'Significant at 90% CI'
        ELSE 'Not statistically significant'
    END AS significance_verdict
FROM pivoted;

-- -----------------------------------------------------------------------------
-- 6. Time-to-conversion: average and median days_to_conversion by group
--    (faster conversion after exposure is itself a product win)
-- -----------------------------------------------------------------------------
SELECT
    experiment_group,
    COUNT(*)                                    AS converted_users,
    ROUND(AVG(days_to_conversion), 1)           AS avg_days_to_conversion,
    ROUND(
        (SELECT AVG(days_to_conversion) FROM (
            SELECT days_to_conversion,
                   ROW_NUMBER() OVER (ORDER BY days_to_conversion) AS rn,
                   COUNT(*) OVER ()                                AS cnt
            FROM experiments AS x2
            WHERE x2.experiment_group = x1.experiment_group AND x2.converted = 1
        ) WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)), 1
    )                                            AS median_days_to_conversion
FROM experiments AS x1
WHERE converted = 1
GROUP BY experiment_group;

-- -----------------------------------------------------------------------------
-- 7. Weekly conversion rate trend by group (exposure week) — for a
--    control-vs-treatment line chart over the life of the experiment
-- -----------------------------------------------------------------------------
SELECT
    strftime('%Y-W%W', exposure_date) AS exposure_week,
    experiment_group,
    COUNT(*)                          AS users_exposed,
    SUM(converted)                    AS conversions,
    ROUND(100.0 * SUM(converted) / COUNT(*), 1) AS conversion_rate_pct
FROM experiments
GROUP BY exposure_week, experiment_group
ORDER BY exposure_week, experiment_group;
