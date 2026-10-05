"""Synthetic data generator for the Product Analytics portfolio project.

Generates three related datasets that simulate a European mobility app:

* ``users.csv``        — user-level attributes captured at signup.
* ``events.csv``        — a behavioural event stream per user (app opens,
  searches, bookings, payments, engagement actions).
* ``experiments.csv``  — outcomes of a single A/B test
  (``simplified_booking_flow``) derived consistently from the event stream.

Design notes (kept here because they explain *why*, not *what*):

* All users share a single latent ``engagement_score`` per user. Session
  frequency, lifespan (retention), and the probability of taking
  "sticky" actions (enabling notifications, saving a favourite location)
  are all partially driven by this shared score. This produces a
  realistic *correlation* between those actions and retention without
  hard-coding a causal rule, and avoids an artificially perfect
  relationship.
* Acquisition channels get independent modifiers for search intent and
  booking-conversion intent, so Paid Search (high search, lower
  conversion) and Referral (moderate search, higher conversion) diverge
  as required.
* The experiment (``simplified_booking_flow``) is modelled as reducing
  cancellations/failed payments *after* a booking is started, i.e. it
  shifts the outcome distribution of the booking step rather than the
  top-of-funnel search rate. ``experiments.csv`` is derived directly
  from the generated events so the two tables are always consistent
  with each other.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd

import config


# ---------------------------------------------------------------------------
# Channel / platform behavioural modifiers
# ---------------------------------------------------------------------------

CHANNEL_ENGAGEMENT_MOD = {
    "Organic": 0.05,
    "Paid Search": -0.05,
    "Paid Social": -0.03,
    "Referral": 0.12,
    "Partnership": 0.04,
    "Direct": 0.0,
}

CHANNEL_SEARCH_MOD = {
    "Organic": 0.0,
    "Paid Search": 0.08,
    "Paid Social": -0.03,
    "Referral": 0.03,
    "Partnership": 0.0,
    "Direct": 0.02,
}

CHANNEL_BOOKING_MOD = {
    "Organic": 0.0,
    "Paid Search": -0.07,
    "Paid Social": -0.04,
    "Referral": 0.09,
    "Partnership": 0.03,
    "Direct": 0.01,
}

PLATFORM_ENGAGEMENT_MOD = {"iOS": 0.02, "Android": 0.0, "Web": -0.06}

# P(booking_completed | booking_started) baseline, before experiment uplift
PLATFORM_COMPLETION_RATE = {"iOS": 0.72, "Android": 0.68, "Web": 0.64}

PAYMENT_WEIGHTS_BY_DEVICE = {
    "iOS": {"Card": 0.30, "PayPal": 0.15, "Apple Pay": 0.40, "Google Pay": 0.02, "Cash": 0.10, "None": 0.03},
    "Android": {"Card": 0.30, "PayPal": 0.15, "Apple Pay": 0.02, "Google Pay": 0.40, "Cash": 0.10, "None": 0.03},
    "Web": {"Card": 0.48, "PayPal": 0.30, "Apple Pay": 0.02, "Google Pay": 0.02, "Cash": 0.12, "None": 0.06},
}

FAILED_PAYMENT_METHODS = ["Card", "PayPal", "Apple Pay", "Google Pay"]


@dataclass
class UserProfile:
    """Derived, per-user generation parameters (not written to CSV)."""

    user_id: str
    signup_date: date
    country: str
    city: str
    platform: str
    acquisition_channel: str
    age_group: Optional[str]
    experiment_group: str
    first_device_type: str
    engagement_score: float = 0.0
    lifespan_days: int = 0
    session_offsets: list = field(default_factory=list)


def ensure_directories() -> None:
    """Create output directories if they do not already exist."""
    config.DATA_RAW_DIR.mkdir(parents=True, exist_ok=True)
    config.DATA_PROCESSED_DIR.mkdir(parents=True, exist_ok=True)


def _weighted_choice(rng: np.random.Generator, options: list, weights: list) -> str:
    """Draw a single weighted-random category."""
    return options[rng.choice(len(options), p=weights)]


def _random_date(rng: np.random.Generator, start: date, end: date) -> date:
    """Draw a uniformly random date in [start, end]."""
    span = (end - start).days
    return start + timedelta(days=int(rng.integers(0, span + 1)))


def generate_users(rng: np.random.Generator, n_users: int) -> tuple[pd.DataFrame, list[UserProfile]]:
    """Generate the users dataset and matching internal generation profiles.

    Args:
        rng: seeded NumPy random Generator.
        n_users: number of user records to create.

    Returns:
        A tuple of (users DataFrame, list of UserProfile objects used
        internally by :func:`generate_events`).
    """
    signup_window_end = config.END_DATE - timedelta(days=45)
    profiles: list[UserProfile] = []

    for i in range(1, n_users + 1):
        user_id = f"U{i:05d}"
        country = _weighted_choice(rng, config.COUNTRIES, [0.30, 0.12, 0.22, 0.16, 0.20])
        city = config.COUNTRY_CITIES[country][rng.integers(0, len(config.COUNTRY_CITIES[country]))]
        platform = _weighted_choice(rng, config.PLATFORMS, config.PLATFORM_WEIGHTS)
        channel = _weighted_choice(rng, config.ACQUISITION_CHANNELS, config.ACQUISITION_CHANNEL_WEIGHTS)
        age_group = _weighted_choice(rng, config.AGE_GROUPS, config.AGE_GROUP_WEIGHTS)
        if rng.random() < 0.03:
            age_group = None  # realistic: some users decline to state age
        experiment_group = _weighted_choice(rng, config.EXPERIMENT_GROUPS, [0.5, 0.5])
        signup_dt = _random_date(rng, config.START_DATE, signup_window_end)

        # First device usually matches platform; Web users occasionally
        # signed up via a mobile browser on an iOS/Android device.
        if platform == "Web" and rng.random() < 0.25:
            first_device = "iOS" if rng.random() < 0.55 else "Android"
        else:
            first_device = platform

        engagement = rng.beta(2.2, 3.0) + CHANNEL_ENGAGEMENT_MOD[channel] + PLATFORM_ENGAGEMENT_MOD[platform]
        engagement = float(np.clip(engagement, 0.03, 0.98))

        max_lifespan = (config.END_DATE - signup_dt).days
        long_term_prob = 0.15 + 0.5 * engagement
        r = rng.random()
        if r < 0.35:
            lifespan = int(rng.integers(1, 11))
        elif r < 0.35 + (1 - long_term_prob) * 0.55:
            lifespan = int(rng.integers(10, 91))
        else:
            lifespan = int(rng.integers(90, 451))
        lifespan = min(lifespan, max_lifespan) if max_lifespan > 0 else 1
        lifespan = max(lifespan, 1)

        profile = UserProfile(
            user_id=user_id,
            signup_date=signup_dt,
            country=country,
            city=city,
            platform=platform,
            acquisition_channel=channel,
            age_group=age_group,
            experiment_group=experiment_group,
            first_device_type=first_device,
            engagement_score=engagement,
            lifespan_days=lifespan,
        )
        profiles.append(profile)

    users_df = pd.DataFrame(
        [
            {
                "user_id": p.user_id,
                "signup_date": p.signup_date.isoformat(),
                "country": p.country,
                "city": p.city,
                "platform": p.platform,
                "acquisition_channel": p.acquisition_channel,
                "age_group": p.age_group,
                "experiment_group": p.experiment_group,
                "first_device_type": p.first_device_type,
            }
            for p in profiles
        ]
    )
    return users_df, profiles


def _session_offsets(rng: np.random.Generator, profile: UserProfile) -> list[int]:
    """Determine day-offsets (from signup) at which a user has a session."""
    monthly_sessions = 1.45 + profile.engagement_score * 7.1
    expected_sessions = max(1.0, monthly_sessions * (profile.lifespan_days / 30.0))
    n_sessions = max(1, int(rng.poisson(expected_sessions)))
    n_sessions = min(n_sessions, 120)  # sanity cap for extreme outliers

    if n_sessions == 1:
        return [0]

    offsets = sorted(int(x) for x in rng.integers(0, profile.lifespan_days + 1, size=n_sessions - 1))
    return [0] + offsets


def _payment_method(rng: np.random.Generator, device_type: str, failed: bool = False) -> str:
    if failed:
        weights = [PAYMENT_WEIGHTS_BY_DEVICE[device_type][m] for m in FAILED_PAYMENT_METHODS]
        weights = np.array(weights) / sum(weights)
        return FAILED_PAYMENT_METHODS[rng.choice(len(FAILED_PAYMENT_METHODS), p=weights)]
    methods = list(PAYMENT_WEIGHTS_BY_DEVICE[device_type].keys())
    weights = list(PAYMENT_WEIGHTS_BY_DEVICE[device_type].values())
    return methods[rng.choice(len(methods), p=weights)]


def _session_device(rng: np.random.Generator, profile: UserProfile) -> str:
    if rng.random() < 0.05 and profile.platform != "Web":
        return "Web" if rng.random() < 0.5 else ("Android" if profile.platform == "iOS" else "iOS")
    return profile.platform


def generate_events(
    rng: np.random.Generator, profiles: list[UserProfile]
) -> pd.DataFrame:
    """Generate the behavioural event stream for all users.

    Booking completion always follows search_started -> search_completed
    -> booking_started in the same session; revenue is only attached to
    booking_completed events; cancelled/failed events carry no revenue.
    """
    rows: list[dict] = []
    event_counter = 0
    notif_users: set[str] = set()
    fav_loc_users: set[str] = set()

    for profile in profiles:
        offsets = _session_offsets(rng, profile)
        has_enabled_notification = False
        has_added_favourite = False

        # "sticky" actions correlate with engagement_score (shared latent
        # driver of retention), not with each other causally.
        will_enable_notification = rng.random() < (0.15 + 0.45 * profile.engagement_score)
        will_add_favourite = rng.random() < (0.10 + 0.40 * profile.engagement_score)
        notif_session_idx = rng.integers(0, max(1, min(3, len(offsets)))) if will_enable_notification else -1
        fav_session_idx = rng.integers(0, max(1, min(4, len(offsets)))) if will_add_favourite else -1

        search_prob = 0.16 + 0.26 * profile.engagement_score + 0.6 * CHANNEL_SEARCH_MOD[profile.acquisition_channel]
        search_prob = float(np.clip(search_prob, 0.04, 0.75))
        search_complete_prob = 0.78
        booking_start_prob = (
            0.15 + 0.13 * profile.engagement_score + 0.6 * CHANNEL_BOOKING_MOD[profile.acquisition_channel]
        )
        booking_start_prob = float(np.clip(booking_start_prob, 0.03, 0.60))

        completion_rate = PLATFORM_COMPLETION_RATE[profile.platform]
        if profile.experiment_group == "treatment":
            completion_rate = min(0.95, completion_rate + config.TREATMENT_CONVERSION_UPLIFT + 0.10)

        for s_idx, offset in enumerate(offsets):
            session_id = f"{profile.user_id}_S{s_idx + 1:03d}"
            session_date = profile.signup_date + timedelta(days=offset)
            if session_date > config.END_DATE:
                continue
            device_type = _session_device(rng, profile)

            base_time = datetime.combine(session_date, datetime.min.time()) + timedelta(
                hours=int(rng.integers(6, 23)), minutes=int(rng.integers(0, 60))
            )
            cursor = base_time

            def add_event(name: str, revenue=np.nan, distance=np.nan, payment=np.nan, dev=None):
                nonlocal event_counter, cursor
                event_counter += 1
                cursor += timedelta(minutes=int(rng.integers(1, 6)))
                rows.append(
                    {
                        "event_id": f"EVT{event_counter:08d}",
                        "user_id": profile.user_id,
                        "event_time": cursor.isoformat(sep=" "),
                        "event_date": cursor.date().isoformat(),
                        "session_id": session_id,
                        "event_name": name,
                        "product_area": config.EVENT_PRODUCT_AREA[name],
                        "device_type": dev if dev is not None else device_type,
                        "revenue": revenue,
                        "ride_distance_km": distance,
                        "payment_method": payment,
                    }
                )

            add_event("app_open")

            if s_idx == 0:
                add_event("signup_completed")
                if rng.random() < 0.65:
                    add_event("location_permission_granted")
            elif s_idx == 1 and rng.random() < 0.20:
                add_event("location_permission_granted")

            if s_idx == notif_session_idx and not has_enabled_notification:
                add_event("notification_enabled")
                has_enabled_notification = True
                notif_users.add(profile.user_id)

            if s_idx == fav_session_idx and not has_added_favourite:
                add_event("favourite_location_added")
                has_added_favourite = True
                fav_loc_users.add(profile.user_id)

            if rng.random() < 0.12:
                add_event("promo_viewed")

            if rng.random() < search_prob:
                add_event("search_started")
                if rng.random() < search_complete_prob:
                    add_event("search_completed")
                    if rng.random() < 0.55:
                        add_event("ride_option_viewed")

                    if rng.random() < booking_start_prob:
                        distance = float(
                            np.clip(rng.normal(config.RIDE_DISTANCE_MEAN, config.RIDE_DISTANCE_STD),
                                     config.RIDE_DISTANCE_MIN, config.RIDE_DISTANCE_MAX)
                        )
                        add_event("booking_started", distance=distance)

                        outcome_roll = rng.random()
                        if outcome_roll < completion_rate:
                            revenue = float(
                                np.clip(rng.normal(config.REVENUE_MEAN, config.REVENUE_STD),
                                        config.REVENUE_MIN, config.REVENUE_MAX)
                            )
                            payment = _payment_method(rng, device_type)
                            add_event(
                                "booking_completed",
                                revenue=revenue,
                                distance=distance,
                                payment=payment,
                            )
                            if rng.random() < 0.50:
                                add_event("rating_submitted")
                        elif outcome_roll < completion_rate + 0.20:
                            add_event("booking_cancelled", distance=distance)
                        else:
                            payment = _payment_method(rng, device_type, failed=True)
                            add_event("payment_failed", payment=payment)
                            if rng.random() < 0.15:
                                add_event("support_contacted")

            if rng.random() < 0.02:
                add_event("support_contacted")

    events_df = pd.DataFrame(rows)
    events_df.sort_values(["user_id", "event_time"], inplace=True)
    events_df.reset_index(drop=True, inplace=True)
    return events_df


def generate_experiments(users_df: pd.DataFrame, events_df: pd.DataFrame) -> pd.DataFrame:
    """Derive experiment outcomes directly from the generated events.

    ``exposure_date`` is the user's signup date (assignment happens at
    signup for this always-on booking-flow experiment). ``converted`` is
    True if the user has at least one ``booking_completed`` event.
    """
    bookings = (
        events_df[events_df["event_name"] == "booking_completed"]
        .groupby("user_id")["event_date"]
        .min()
        .rename("conversion_date")
    )

    exp = users_df[["user_id", "signup_date", "experiment_group"]].copy()
    exp = exp.merge(bookings, on="user_id", how="left")
    exp["experiment_name"] = config.EXPERIMENT_NAME
    exp["exposure_date"] = exp["signup_date"]
    exp["converted"] = exp["conversion_date"].notna()

    exposure_dt = pd.to_datetime(exp["exposure_date"])
    conversion_dt = pd.to_datetime(exp["conversion_date"])
    exp["days_to_conversion"] = (conversion_dt - exposure_dt).dt.days

    exp = exp[
        [
            "user_id",
            "experiment_name",
            "experiment_group",
            "exposure_date",
            "converted",
            "conversion_date",
            "days_to_conversion",
        ]
    ]
    return exp.reset_index(drop=True)


def _print_stats(users_df: pd.DataFrame, events_df: pd.DataFrame, experiments_df: pd.DataFrame) -> None:
    print("=" * 60)
    print("SYNTHETIC DATA GENERATION SUMMARY")
    print("=" * 60)
    print(f"Users:        {len(users_df):,} rows -> {config.USERS_FILE}")
    print(f"Events:       {len(events_df):,} rows -> {config.EVENTS_FILE}")
    print(f"Experiments:  {len(experiments_df):,} rows -> {config.EXPERIMENTS_FILE}")
    print("-" * 60)
    print(f"Signup date range: {users_df['signup_date'].min()} -> {users_df['signup_date'].max()}")
    print(f"Event date range:  {events_df['event_date'].min()} -> {events_df['event_date'].max()}")
    conv_rate = experiments_df.groupby("experiment_group")["converted"].mean()
    print("-" * 60)
    print("Conversion rate by experiment group:")
    for grp, rate in conv_rate.items():
        print(f"  {grp:10s}: {rate:.2%}")
    print("=" * 60)


def main() -> None:
    """Entry point: generate all three datasets and write them to disk."""
    try:
        ensure_directories()
        rng = np.random.default_rng(config.RANDOM_SEED)

        print(f"Generating {config.NUM_USERS:,} users...")
        users_df, profiles = generate_users(rng, config.NUM_USERS)

        print("Generating behavioural events...")
        events_df = generate_events(rng, profiles)

        if not (config.MIN_EVENTS <= len(events_df) <= config.MAX_EVENTS):
            print(
                f"WARNING: generated {len(events_df):,} events, outside the "
                f"target range [{config.MIN_EVENTS:,}, {config.MAX_EVENTS:,}]."
            )

        print("Deriving experiment outcomes...")
        experiments_df = generate_experiments(users_df, events_df)

        print("Writing CSV files...")
        users_df.to_csv(config.USERS_FILE, index=False)
        events_df.to_csv(config.EVENTS_FILE, index=False)
        experiments_df.to_csv(config.EXPERIMENTS_FILE, index=False)

        _print_stats(users_df, events_df, experiments_df)

    except Exception as exc:  # noqa: BLE001 - top-level generation guard
        print(f"ERROR during data generation: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
