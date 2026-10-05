# Phase 2 Summary: SQL Analytics Layer

> **Scope note:** these findings are derived from the synthetic dataset
> generated in Phase 1 (`data/raw/*.csv`, seed-reproducible, 5,000 users /
> 141,813 events / 18-month window). They demonstrate the analytical
> approach and SQL techniques a Product Analyst would apply — they do not
> describe a real company. All figures below were produced by running the
> queries in `sql/01`–`sql/10` against `data/processed/analytics.db`
> (built via `src/build_database.py`).

---

## 1. Important KPIs (current state)

| KPI | Value | Source |
|---|---|---|
| Total users | 5,000 | `03_kpi_dashboard.sql` Q1 |
| Ever-active users | 5,000 (100%) | `03_kpi_dashboard.sql` Q1 |
| Activation rate (search + booking within 7 days) | 6.3% | `03_kpi_dashboard.sql` Q6 |
| Conversion rate (lifetime, ≥1 booking) | 28.7% | `03_kpi_dashboard.sql` Q7 |
| Total revenue | €39,590 | `03_kpi_dashboard.sql` Q8 |
| ARPU (all users) | €7.92 | `03_kpi_dashboard.sql` Q8 |
| ARPPU (paying users only) | €27.61 | `03_kpi_dashboard.sql` Q8 |
| Average booking value (AOV) | €14.50 | `03_kpi_dashboard.sql` Q8 |
| Bookings per paying user | 1.9 | `03_kpi_dashboard.sql` Q8 |
| Day 1 / Day 7 / Day 30 retention | 10.2% / 9.3% / 7.1% | `05_retention.sql` Q1 |
| Churn rate (30+ days inactive vs. dataset end) | 83.7% | `05_retention.sql` Q5 |
| Booking cancellation rate | 17.5% of attempts | `04_funnel_analysis.sql` Q3 |

---

## 2. Key findings

**Funnel: the biggest leak is between search and booking, not at checkout.**
Of 5,000 signups, 69.2% start a search, but only 33.1% ever start a
booking — a 52.1% drop-off between `search_started` and `booking_started`
(`04_funnel_analysis.sql` Q2). Once a user *does* start a booking, 86.5%
of them complete it. This means the product's checkout/payment flow is
comparatively healthy; the real opportunity is in the search-to-decision
step. Confirmed by the abandonment-point query (`04` Q4): among sessions
that searched but never converted, 37.9% stopped right after viewing ride
options and 30.4% stopped right after search results — i.e. most
abandonment happens while comparing options, before ever attempting to
book.

**Acquisition channel quality varies far more than channel volume.**
Referral users convert at 40.0% and carry an ARPU of €13.03 — roughly
2.4x the ARPU of Paid Search (€5.43) and Paid Social (€5.39)
(`08_segmentation.sql` Q4). Paid Search actually drives strong top-of-funnel
search activity (72.2% search rate) but a comparatively weak booking-start
rate (37.8%) — a lot of window-shopping that doesn't convert to booking
intent (`04_funnel_analysis.sql` Q5). Both paid channels sit 6–8pp below
the cross-channel average conversion rate despite above-average signup
volume (`10_business_recommendations.sql` Q3).

**Engagement features correlate strongly with retention — and the effect stacks.**
Users who adopted all three tracked engagement actions (notifications,
favourite location, viewed a promo) show 14.7% Day 30 retention vs. 2.0%
for users who adopted none — a clean dose-response gradient (2.0% → 6.2%
→ 11.3% → 14.7% as adopted-feature count rises from 0 to 3)
(`07_feature_adoption.sql` Q4). This is an observational correlation, not
a causal estimate (see caveats below), but the gradient is consistent
enough to be a strong lead for a follow-up experiment.

**Revenue is concentrated in a small user segment.** The top value tier
(9.6% of users, "High value") generates 62.9% of all revenue; 71.3% of
users have never completed a booking at all (`08_segmentation.sql` Q5).
This is a standard Pareto pattern for a mobility app but worth flagging:
retention and reactivation efforts aimed at the "Non-payer" segment have
the largest addressable population, while the "High value" segment is
where churn would hurt revenue the most per lost user.

**Referral converts fastest to a first booking but retains worst.**
Referral has the highest conversion rate (40.0%) and ARPU (€13.03) of any
channel, but the *lowest* Day 30 retention of all channels (6.0%, vs. an
overall average of 7.1%) (`10_business_recommendations.sql` Q5). This
suggests referred users convert on trust/incentive quickly but don't
necessarily become habitual users — an onboarding/engagement gap worth
investigating.

**Platform: Web underperforms iOS and Android on every metric measured.**
Web has the lowest conversion rate (24.0% vs. 30.0% iOS / 28.8% Android),
lowest ARPU (€6.03 vs. €8.48 / €7.91), and lowest Day 30 retention (5.6%
vs. 7.7% / 6.9%) (`08_segmentation.sql` Q2, `05_retention.sql` Q3).

**The `simplified_booking_flow` experiment shows a real, statistically
significant improvement.** Treatment conversion is 30.45% vs. 26.89% for
control — a +3.55pp absolute / +13.2% relative uplift, with a
two-proportion z-statistic of 2.78 (significant at 99% CI). ARPU also
rises significantly, €8.80 vs. €7.02 (+25.4%, z = 3.64, significant at
99% CI) (`09_ab_testing.sql` Q2, Q4, Q5). One nuance: treatment users take
slightly *longer* to convert on average (60.9 vs. 57.8 days) — the
simplified flow appears to convert more users overall rather than
accelerating the ones who were already going to convert
(`09_ab_testing.sql` Q6).

---

## 3. Business recommendations

1. **Prioritise the search-to-booking-start step over checkout polish.**
   The funnel data shows 52% of the drop-off happens before a booking is
   even attempted, concentrated right after viewing ride options. A/B test
   changes to ride-option presentation, pricing transparency, or a
   "quick rebook" shortcut before investing further in the payment flow,
   which already converts at 86.5%.

2. **Reallocate a portion of Paid Search / Paid Social budget toward
   Referral and Partnership programs.** Referral delivers 2.4x the ARPU of
   paid channels at a lower cost basis; a formal referral-incentive
   program could scale a channel that already outperforms organically.

3. **Roll out `simplified_booking_flow` to 100% of users.** The uplift is
   positive and statistically significant on both conversion and revenue
   with no evidence of a downside — this clears the standard bar for
   shipping a winning experiment (`10_business_recommendations.sql` Q6).

4. **Design a targeted onboarding nudge for Referral users** to convert
   their fast initial trust into habitual usage — e.g. a second-booking
   incentive in the first two weeks — given their conversion strength is
   not currently translating into retention.

5. **Investigate the Web platform experience specifically.** Its
   underperformance is consistent across conversion, ARPU, and retention,
   which points to a platform-level UX or performance issue rather than a
   single funnel step.

6. **Run a causal (randomised) follow-up test on notification opt-in
   and favourite-location prompts.** The correlational retention lift is
   large enough (up to 3–7x on Day 30 retention) to justify testing
   whether actively prompting users to enable these features — rather than
   observing who does so organically — produces a similar effect.

---

## 4. Interesting trends

- **Monthly cohorts show a consistent early decay curve**: month-0 100% →
  month-1 ~58% → month-2 ~45% → month-3 ~34%, flattening out in the
  low-teens/single digits by month 6+ (`06_cohort_analysis.sql` Q2). The
  steepest drop is in the first month after signup — this is where a
  retention intervention would have the most leverage.
- **Revenue per cohort user declines faster than the retention curve**,
  suggesting that the users who do stick around past month 2–3 book less
  frequently on average than the cohort's early, highly-engaged bookers
  (`06_cohort_analysis.sql` Q3).
- **Stickiness (avg DAU / MAU) rises steadily over the observed period**
  (from ~7% in the first month to ~12% by month 8), indicating the overall
  platform's engagement depth improves as the user base matures — likely
  a mix effect as early, highly-active cohorts accumulate
  (`03_kpi_dashboard.sql` Q5).

---

## 5. Potential product improvements

- A lightweight "why didn't this work" prompt (or simplified retry flow)
  triggered specifically after `payment_failed`, since failed payments
  show an elevated support-contact rate immediately afterward.
- A post-search "still deciding?" nudge (push notification or in-app
  banner) targeted at sessions that reach `ride_option_viewed` without
  proceeding — the single largest abandonment point in the funnel.
- A guided first-two-weeks engagement flow that actively prompts
  notification opt-in and favourite-location setup during onboarding,
  informed by finding #3 above.
- A Referral-specific retention track (e.g., second-booking incentive)
  to address the conversion/retention mismatch identified for that
  channel.

---

## 6. Methodology caveats

- **Churn rate (83.7%) is right-censored.** It's measured against the
  dataset's last recorded date, so users who signed up in the final weeks
  of the observation window simply haven't had 30 days to prove
  themselves inactive yet. Treat this figure as directionally realistic
  for a mobility app, not a precise operational churn rate.
- **Feature adoption vs. retention/conversion is correlational**, not
  causal. In the underlying data-generation model, both retention and
  the propensity to adopt engagement features are driven by a shared
  latent "engagement" trait, which is exactly the kind of confound real
  observational product data has — hence recommendation #6 (run a real
  experiment) rather than treating the correlation as proof of a lever.
- **Statistical significance in `09_ab_testing.sql`** uses a normal
  approximation (z-test) appropriate for this sample size (~2,500 per
  group); SQLite has no built-in p-value function, so results are
  reported as z-statistics compared against standard critical values
  (1.645 / 1.96 / 2.576 for 90/95/99% two-tailed confidence) rather than
  exact p-values.
