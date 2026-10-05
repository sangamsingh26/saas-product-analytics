"""Pytest suite for the core data quality rules of the generated datasets.

Requires ``data/raw/*.csv`` to already exist (run ``src/generate_data.py``
first). Tests are read-only against the CSVs on disk.
"""

import sys
from pathlib import Path

import pandas as pd
import pytest

SRC_DIR = Path(__file__).resolve().parent.parent / "src"
sys.path.insert(0, str(SRC_DIR))

import config  # noqa: E402


@pytest.fixture(scope="module")
def users() -> pd.DataFrame:
    return pd.read_csv(config.USERS_FILE, parse_dates=["signup_date"])


@pytest.fixture(scope="module")
def events() -> pd.DataFrame:
    return pd.read_csv(config.EVENTS_FILE, parse_dates=["event_time", "event_date"])


@pytest.fixture(scope="module")
def experiments() -> pd.DataFrame:
    return pd.read_csv(config.EXPERIMENTS_FILE, parse_dates=["exposure_date", "conversion_date"])


class TestSchemaPresence:
    def test_users_required_columns(self, users: pd.DataFrame) -> None:
        required = {
            "user_id", "signup_date", "country", "city", "platform",
            "acquisition_channel", "age_group", "experiment_group", "first_device_type",
        }
        assert required.issubset(set(users.columns))

    def test_events_required_columns(self, events: pd.DataFrame) -> None:
        required = {
            "event_id", "user_id", "event_time", "event_date", "session_id",
            "event_name", "product_area", "device_type", "revenue",
            "ride_distance_km", "payment_method",
        }
        assert required.issubset(set(events.columns))

    def test_experiments_required_columns(self, experiments: pd.DataFrame) -> None:
        required = {
            "user_id", "experiment_name", "experiment_group", "exposure_date",
            "converted", "conversion_date", "days_to_conversion",
        }
        assert required.issubset(set(experiments.columns))


class TestPrimaryKeys:
    def test_users_user_id_unique(self, users: pd.DataFrame) -> None:
        assert users["user_id"].is_unique

    def test_events_event_id_unique(self, events: pd.DataFrame) -> None:
        assert events["event_id"].is_unique


class TestReferentialIntegrity:
    def test_events_user_ids_exist_in_users(self, users: pd.DataFrame, events: pd.DataFrame) -> None:
        known_ids = set(users["user_id"])
        assert events["user_id"].isin(known_ids).all()

    def test_experiments_user_ids_exist_in_users(self, users: pd.DataFrame, experiments: pd.DataFrame) -> None:
        known_ids = set(users["user_id"])
        assert experiments["user_id"].isin(known_ids).all()


class TestRowCounts:
    def test_user_count_approx_5000(self, users: pd.DataFrame) -> None:
        assert 4500 <= len(users) <= 5500

    def test_event_count_in_target_range(self, events: pd.DataFrame) -> None:
        assert 100_000 <= len(events) <= 200_000


class TestBusinessLogic:
    def test_event_times_after_signup(self, users: pd.DataFrame, events: pd.DataFrame) -> None:
        merged = events.merge(users[["user_id", "signup_date"]], on="user_id", how="left")
        assert (merged["event_time"].dt.normalize() >= merged["signup_date"]).all()

    def test_revenue_never_negative(self, events: pd.DataFrame) -> None:
        assert (events["revenue"].dropna() >= 0).all()

    def test_revenue_only_on_booking_completed(self, events: pd.DataFrame) -> None:
        non_completed = events[events["event_name"] != "booking_completed"]
        assert non_completed["revenue"].isna().all() or (non_completed["revenue"].fillna(0) == 0).all()

    def test_booking_completed_has_revenue(self, events: pd.DataFrame) -> None:
        completed = events[events["event_name"] == "booking_completed"]
        assert (completed["revenue"] > 0).all()

    def test_cancelled_and_failed_have_no_revenue(self, events: pd.DataFrame) -> None:
        subset = events[events["event_name"].isin(["booking_cancelled", "payment_failed"])]
        assert subset["revenue"].isna().all()

    def test_booking_started_precedes_completed_within_session(self, events: pd.DataFrame) -> None:
        by_session = events.groupby("session_id")["event_name"].apply(set)
        offending = by_session[
            by_session.apply(lambda s: "booking_completed" in s and "booking_started" not in s)
        ]
        assert len(offending) == 0

    def test_search_precedes_booking_within_session(self, events: pd.DataFrame) -> None:
        by_session = events.groupby("session_id")["event_name"].apply(set)
        offending = by_session[
            by_session.apply(lambda s: "booking_started" in s and "search_started" not in s)
        ]
        assert len(offending) == 0


class TestCategoricalDomains:
    def test_country_values_valid(self, users: pd.DataFrame) -> None:
        assert set(users["country"].unique()).issubset(set(config.COUNTRIES))

    def test_platform_values_valid(self, users: pd.DataFrame) -> None:
        assert set(users["platform"].unique()).issubset(set(config.PLATFORMS))

    def test_experiment_group_values_valid(self, users: pd.DataFrame) -> None:
        assert set(users["experiment_group"].unique()).issubset(set(config.EXPERIMENT_GROUPS))

    def test_event_name_values_valid(self, events: pd.DataFrame) -> None:
        assert set(events["event_name"].unique()).issubset(set(config.EVENT_NAMES))


class TestExperimentConsistency:
    def test_experiment_group_matches_users(self, users: pd.DataFrame, experiments: pd.DataFrame) -> None:
        merged = experiments.merge(users[["user_id", "experiment_group"]], on="user_id", suffixes=("_exp", "_user"))
        assert (merged["experiment_group_exp"] == merged["experiment_group_user"]).all()

    def test_converted_flag_matches_booking_events(self, events: pd.DataFrame, experiments: pd.DataFrame) -> None:
        booked_users = set(events[events["event_name"] == "booking_completed"]["user_id"])
        flagged_converted = set(experiments[experiments["converted"]]["user_id"])
        assert booked_users == flagged_converted

    def test_days_to_conversion_non_negative(self, experiments: pd.DataFrame) -> None:
        converted = experiments[experiments["converted"]]
        assert (converted["days_to_conversion"] >= 0).all()


class TestDateRange:
    def test_signup_dates_within_configured_range(self, users: pd.DataFrame) -> None:
        assert users["signup_date"].min() >= pd.Timestamp(config.START_DATE)
        assert users["signup_date"].max() <= pd.Timestamp(config.END_DATE)

    def test_data_spans_at_least_12_months(self, users: pd.DataFrame) -> None:
        span_days = (users["signup_date"].max() - users["signup_date"].min()).days
        assert span_days >= 300
