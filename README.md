# Data Dictionary

> **Synthetic data disclaimer:** All data in this project is randomly
> generated with a fixed random seed (`config.RANDOM_SEED = 42`). No real
> users, events, or company data are represented. Values are constructed
> to be internally consistent and behaviourally realistic (funnels,
> retention patterns, experiment uplift) so the dataset can support a
> credible end-to-end product analytics case study, but they do not
> describe any real mobility app. The dataset is designed purely for
> **portfolio demonstration** purposes.

## Files

| File | Location | Approx. rows | Grain |
|---|---|---|---|
| `users.csv` | `data/raw/` | ~5,000 | one row per user |
| `events.csv` | `data/raw/` | ~120,000–180,000 | one row per event |
| `experiments.csv` | `data/raw/` | ~5,000 | one row per user |

---

## `users.csv`

| Column | Type | Description |
|---|---|---|
| `user_id` | string | Unique user identifier, e.g. `U00001`. |
| `signup_date` | date | Date the user created their account. |
| `country` | category | User's country: `Germany`, `Austria`, `Spain`, `Netherlands`, `France`. |
| `city` | category | User's city, consistent with `country`. |
| `platform` | category | Primary app platform: `iOS`, `Android`, `Web`. |
| `acquisition_channel` | category | How the user was acquired: `Organic`, `Paid Search`, `Paid Social`, `Referral`, `Partnership`, `Direct`. |
| `age_group` | category | Self-reported age band: `18-24`, `25-34`, `35-44`, `45-54`, `55+`. ~3% missing (declined to state). |
| `experiment_group` | category | Assignment for the `simplified_booking_flow` A/B test: `control` or `treatment`. |
| `first_device_type` | category | Device type used at signup (usually matches `platform`, with some Web-via-mobile-browser variation). |

## `events.csv`

| Column | Type | Description |
|---|---|---|
| `event_id` | string | Unique event identifier, e.g. `EVT00000001`. |
| `user_id` | string | Foreign key to `users.csv`. |
| `event_time` | datetime | Full timestamp of the event. Always on/after the user's `signup_date`. |
| `event_date` | date | Date part of `event_time`, for convenient daily aggregation. |
| `session_id` | string | Identifies events belonging to the same app session, e.g. `U00001_S001`. |
| `event_name` | category | See **Event taxonomy** below. |
| `product_area` | category | `Onboarding`, `Search`, `Booking`, `Payments`, `Engagement`, `Support`. Derived from `event_name`. |
| `device_type` | category | Device used for this specific event: `iOS`, `Android`, `Web`. |
| `revenue` | float, nullable | Booking value in EUR. **Only populated for `booking_completed` events**; null everywhere else. |
| `ride_distance_km` | float, nullable | Estimated ride distance. Populated only for `booking_started`, `booking_completed`, and `booking_cancelled` events. |
| `payment_method` | category, nullable | `Card`, `PayPal`, `Apple Pay`, `Google Pay`, `Cash`, `None`. Populated only for `booking_completed` and `payment_failed` events. |

### Event taxonomy

| `event_name` | `product_area` | Notes |
|---|---|---|
| `app_open` | Engagement | First event of every session. |
| `signup_completed` | Onboarding | Fires once, in the user's first session. |
| `location_permission_granted` | Onboarding | Mostly occurs in the first 1–2 sessions. |
| `search_started` | Search | Start of a ride search. |
| `search_completed` | Search | Search returned results. |
| `ride_option_viewed` | Search | User viewed a specific ride option. |
| `promo_viewed` | Engagement | User viewed a promotional banner/offer. |
| `booking_started` | Booking | User began booking a ride. Always preceded by `search_started`/`search_completed` in the same session. |
| `booking_completed` | Booking | Ride successfully booked. Always preceded by `booking_started` in the same session. Only event with revenue. |
| `booking_cancelled` | Booking | Booking was abandoned/cancelled before payment. No revenue. |
| `favourite_location_added` | Engagement | One-time "sticky" engagement action. |
| `notification_enabled` | Engagement | One-time "sticky" engagement action. |
| `support_contacted` | Support | User contacted support (more likely after a `payment_failed`). |
| `payment_failed` | Payments | Payment attempt failed after `booking_started`. No revenue. |
| `rating_submitted` | Engagement | Optional post-booking rating, only after `booking_completed`. |

## `experiments.csv`

| Column | Type | Description |
|---|---|---|
| `user_id` | string | Foreign key to `users.csv`. |
| `experiment_name` | string | Always `simplified_booking_flow` in this dataset. |
| `experiment_group` | category | `control` or `treatment`; always matches `users.experiment_group`. |
| `exposure_date` | date | Date the user was exposed to the experiment (equal to `signup_date` — assignment happens at signup). |
| `converted` | boolean | `True` if the user has at least one `booking_completed` event. |
| `conversion_date` | date, nullable | Date of the user's first `booking_completed` event. Null if not converted. |
| `days_to_conversion` | int, nullable | Days between `exposure_date` and `conversion_date`. Null if not converted. |

---

## Metric definitions

These definitions are the intended basis for later analysis phases (not yet computed in Phase 1):

- **Activation** — a user completes at least one `search_completed` and one `booking_completed` event within 7 days of `signup_date`.
- **Conversion** — a user completes at least one `booking_completed` event (see `experiments.converted`).
- **Retention** — user activity (any event) measured at Day 1, Day 7, and Day 30 after `signup_date`.
- **Churn** — no user activity for at least 30 consecutive days following the user's last recorded event.

## Known modelling assumptions

- Sticky engagement actions (`notification_enabled`, `favourite_location_added`) and longer retention are both driven by a shared per-user latent "engagement" propensity, rather than one directly causing the other — this mirrors how these correlations usually arise in real product data.
- The `simplified_booking_flow` experiment is modelled as reducing cancellations/failed payments *after* a booking is started (i.e. it improves booking completion rate), not the top-of-funnel search rate.
- `Paid Search` acquisition drives more search activity but comparatively lower booking conversion; `Referral` drives less search volume but higher conversion — reflecting different user intent by channel.
