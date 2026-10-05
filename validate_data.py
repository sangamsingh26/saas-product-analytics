"""Data quality validation for the generated portfolio datasets.

Runs a series of structural and business-logic checks against
``users.csv``, ``events.csv``, and ``experiments.csv`` and prints a
human-readable report. Checks are grouped into:

* CRITICAL  — a failure indicates the datasets are unusable for
  downstream analysis (e.g. missing columns, orphan foreign keys,
  negative revenue). Any critical failure causes a non-zero exit code.
* WARNING   — a failure worth knowing about but not blocking (e.g.
  null rates above an expected threshold).
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field

import pandas as pd

import config


@dataclass
class ValidationReport:
    """Collects check results for pretty-printing at the end."""

    passed: list = field(default_factory=list)
    warnings: list = field(default_factory=list)
    failures: list = field(default_factory=list)

    def ok(self, msg: str) -> None:
        self.passed.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def fail(self, msg: str) -> None:
        self.failures.append(msg)

    @property
    def has_critical_failures(self) -> bool:
        return len(self.failures) > 0


REQUIRED_USER_COLUMNS = [
    "user_id", "signup_date", "country", "city", "platform",
    "acquisition_channel", "age_group", "experiment_group", "first_device_type",
]

REQUIRED_EVENT_COLUMNS = [
    "event_id", "user_id", "event_time", "event_date", "session_id",
    "event_name", "product_area", "device_type", "revenue",
    "ride_distance_km", "payment_method",
]

REQUIRED_EXPERIMENT_COLUMNS = [
    "user_id", "experiment_name", "experiment_group", "exposure_date",
    "converted", "conversion_date", "days_to_conversion",
]

# Columns where some missingness is expected and acceptable, with a
# maximum tolerated null rate before it is flagged as a warning.
EXPECTED_NULL_RATE_MAX = {
    "age_group": 0.08,
    "revenue": 0.99,          # only populated for booking_completed events
    "ride_distance_km": 0.97,  # only populated for booking-related events
    "payment_method": 0.99,   # only populated for payment-related events
    "conversion_date": 0.90,  # only populated for converted users
    "days_to_conversion": 0.90,
}


def load_datasets() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Load the three raw CSV datasets from disk."""
    users = pd.read_csv(config.USERS_FILE, parse_dates=["signup_date"])
    events = pd.read_csv(config.EVENTS_FILE, parse_dates=["event_time", "event_date"])
    experiments = pd.read_csv(
        config.EXPERIMENTS_FILE, parse_dates=["exposure_date", "conversion_date"]
    )
    return users, events, experiments


def check_required_columns(report: ValidationReport, df: pd.DataFrame, name: str, required: list) -> None:
    missing = [c for c in required if c not in df.columns]
    if missing:
        report.fail(f"[{name}] Missing required columns: {missing}")
    else:
        report.ok(f"[{name}] All required columns present ({len(required)} columns)")


def check_duplicate_keys(report: ValidationReport, df: pd.DataFrame, name: str, key: str) -> None:
    dup_count = int(df[key].duplicated().sum())
    if dup_count > 0:
        report.fail(f"[{name}] {dup_count} duplicate values found in primary key '{key}'")
    else:
        report.ok(f"[{name}] No duplicate primary keys in '{key}'")


def check_orphan_user_ids(report: ValidationReport, child: pd.DataFrame, child_name: str, users: pd.DataFrame) -> None:
    known_ids = set(users["user_id"])
    orphan_count = int((~child["user_id"].isin(known_ids)).sum())
    if orphan_count > 0:
        report.fail(f"[{child_name}] {orphan_count} rows reference a user_id not present in users.csv")
    else:
        report.ok(f"[{child_name}] All user_id values exist in users.csv")


def check_event_time_after_signup(report: ValidationReport, events: pd.DataFrame, users: pd.DataFrame) -> None:
    merged = events.merge(users[["user_id", "signup_date"]], on="user_id", how="left")
    invalid = merged[merged["event_time"].dt.normalize() < merged["signup_date"]]
    if len(invalid) > 0:
        report.fail(f"[events] {len(invalid)} events occur before the user's signup_date")
    else:
        report.ok("[events] All event times occur on/after each user's signup_date")


def check_negative_revenue(report: ValidationReport, events: pd.DataFrame) -> None:
    negative = events[events["revenue"] < 0]
    if len(negative) > 0:
        report.fail(f"[events] {len(negative)} events have negative revenue")
    else:
        report.ok("[events] No negative revenue values")


def check_revenue_only_on_completed(report: ValidationReport, events: pd.DataFrame) -> None:
    bad = events[(events["revenue"].notna()) & (events["revenue"] > 0) & (events["event_name"] != "booking_completed")]
    if len(bad) > 0:
        report.fail(f"[events] {len(bad)} non-booking_completed events have positive revenue")
    else:
        report.ok("[events] Revenue is only present on booking_completed events")

    missing_revenue = events[(events["event_name"] == "booking_completed") & (events["revenue"].isna() | (events["revenue"] <= 0))]
    if len(missing_revenue) > 0:
        report.fail(f"[events] {len(missing_revenue)} booking_completed events are missing positive revenue")
    else:
        report.ok("[events] All booking_completed events have positive revenue")

    cancelled_or_failed = events[events["event_name"].isin(["booking_cancelled", "payment_failed"])]
    bad_cf = cancelled_or_failed[cancelled_or_failed["revenue"].notna() & (cancelled_or_failed["revenue"] > 0)]
    if len(bad_cf) > 0:
        report.fail(f"[events] {len(bad_cf)} booking_cancelled/payment_failed events incorrectly have revenue")
    else:
        report.ok("[events] booking_cancelled/payment_failed events carry no revenue")


def check_categorical_values(report: ValidationReport, users: pd.DataFrame, events: pd.DataFrame, experiments: pd.DataFrame) -> None:
    checks = [
        ("users", "country", users["country"], config.COUNTRIES),
        ("users", "platform", users["platform"], config.PLATFORMS),
        ("users", "acquisition_channel", users["acquisition_channel"], config.ACQUISITION_CHANNELS),
        ("users", "age_group", users["age_group"].dropna(), config.AGE_GROUPS),
        ("users", "experiment_group", users["experiment_group"], config.EXPERIMENT_GROUPS),
        ("events", "event_name", events["event_name"], config.EVENT_NAMES),
        ("events", "product_area", events["product_area"], config.PRODUCT_AREAS),
        ("events", "device_type", events["device_type"], config.DEVICE_TYPES),
        ("events", "payment_method", events["payment_method"].dropna(), config.PAYMENT_METHODS),
        ("experiments", "experiment_group", experiments["experiment_group"], config.EXPERIMENT_GROUPS),
    ]
    any_bad = False
    for df_name, col, series, allowed in checks:
        invalid_values = set(series.unique()) - set(allowed)
        if invalid_values:
            report.fail(f"[{df_name}] Column '{col}' has invalid category values: {invalid_values}")
            any_bad = True
    if not any_bad:
        report.ok("[all] All categorical columns contain only allowed values")


def check_experiment_group_consistency(report: ValidationReport, users: pd.DataFrame, experiments: pd.DataFrame) -> None:
    merged = experiments.merge(users[["user_id", "experiment_group"]], on="user_id", suffixes=("_exp", "_user"))
    mismatched = merged[merged["experiment_group_exp"] != merged["experiment_group_user"]]
    if len(mismatched) > 0:
        report.fail(f"[experiments] {len(mismatched)} users have mismatched experiment_group vs users.csv")
    else:
        report.ok("[experiments] experiment_group is consistent with users.csv")


def check_date_range(report: ValidationReport, users: pd.DataFrame, events: pd.DataFrame) -> None:
    start, end = pd.Timestamp(config.START_DATE), pd.Timestamp(config.END_DATE)
    bad_users = users[(users["signup_date"] < start) | (users["signup_date"] > end)]
    if len(bad_users) > 0:
        report.fail(f"[users] {len(bad_users)} signup_date values fall outside the configured date range")
    else:
        report.ok("[users] All signup_date values fall within the configured date range")

    bad_events = events[(events["event_date"] < start) | (events["event_date"] > end)]
    if len(bad_events) > 0:
        report.fail(f"[events] {len(bad_events)} event_date values fall outside the configured date range")
    else:
        report.ok("[events] All event_date values fall within the configured date range")

    span_days = (users["signup_date"].max() - users["signup_date"].min()).days
    if span_days < 300:
        report.warn(f"[users] signup_date span is only {span_days} days (expected >= ~365)")
    else:
        report.ok(f"[users] signup_date span covers {span_days} days (>= 12 months)")


def check_null_rates(report: ValidationReport, df: pd.DataFrame, name: str) -> None:
    for col in df.columns:
        null_rate = float(df[col].isna().mean())
        max_allowed = EXPECTED_NULL_RATE_MAX.get(col, 0.01)
        if null_rate > max_allowed:
            report.warn(f"[{name}] Column '{col}' null rate {null_rate:.1%} exceeds expected max {max_allowed:.0%}")
    report.ok(f"[{name}] Null rate check complete")


def check_funnel_logic(report: ValidationReport, events: pd.DataFrame) -> None:
    """Booking-related events should generally follow the expected order."""
    session_events = events.groupby("session_id")["event_name"].apply(list)

    sessions_with_booking_completed_no_start = 0
    sessions_with_booking_no_search = 0

    for names in session_events:
        if "booking_completed" in names and "booking_started" not in names:
            sessions_with_booking_completed_no_start += 1
        if "booking_started" in names and "search_started" not in names:
            sessions_with_booking_no_search += 1

    if sessions_with_booking_completed_no_start > 0:
        report.fail(
            f"[events] {sessions_with_booking_completed_no_start} sessions have "
            "booking_completed without a preceding booking_started"
        )
    else:
        report.ok("[events] Every booking_completed event has a booking_started in the same session")

    if sessions_with_booking_no_search > 0:
        report.fail(
            f"[events] {sessions_with_booking_no_search} sessions have "
            "booking_started without a preceding search_started"
        )
    else:
        report.ok("[events] Every booking_started event has a search_started in the same session")


def check_experiment_conversion_matches_events(report: ValidationReport, experiments: pd.DataFrame, events: pd.DataFrame) -> None:
    booked_users = set(events[events["event_name"] == "booking_completed"]["user_id"])
    flagged_converted = set(experiments[experiments["converted"]]["user_id"])
    if booked_users != flagged_converted:
        mismatch = len(booked_users.symmetric_difference(flagged_converted))
        report.fail(f"[experiments] {mismatch} users have inconsistent 'converted' flag vs booking_completed events")
    else:
        report.ok("[experiments] 'converted' flag is fully consistent with booking_completed events")


def print_report(report: ValidationReport) -> None:
    print("=" * 70)
    print("DATA VALIDATION REPORT")
    print("=" * 70)
    print(f"\nPASSED ({len(report.passed)})")
    for msg in report.passed:
        print(f"  [OK]   {msg}")

    if report.warnings:
        print(f"\nWARNINGS ({len(report.warnings)})")
        for msg in report.warnings:
            print(f"  [WARN] {msg}")

    if report.failures:
        print(f"\nCRITICAL FAILURES ({len(report.failures)})")
        for msg in report.failures:
            print(f"  [FAIL] {msg}")

    print("\n" + "=" * 70)
    status = "FAILED" if report.has_critical_failures else "PASSED"
    print(f"VALIDATION RESULT: {status}  "
          f"({len(report.passed)} passed, {len(report.warnings)} warnings, {len(report.failures)} critical failures)")
    print("=" * 70)


def main() -> None:
    """Load datasets, run all checks, print the report, set exit code."""
    report = ValidationReport()
    try:
        users, events, experiments = load_datasets()
    except FileNotFoundError as exc:
        print(f"ERROR: could not load datasets: {exc}", file=sys.stderr)
        sys.exit(1)

    check_required_columns(report, users, "users", REQUIRED_USER_COLUMNS)
    check_required_columns(report, events, "events", REQUIRED_EVENT_COLUMNS)
    check_required_columns(report, experiments, "experiments", REQUIRED_EXPERIMENT_COLUMNS)

    check_duplicate_keys(report, users, "users", "user_id")
    check_duplicate_keys(report, events, "events", "event_id")

    check_orphan_user_ids(report, events, "events", users)
    check_orphan_user_ids(report, experiments, "experiments", users)

    check_event_time_after_signup(report, events, users)
    check_negative_revenue(report, events)
    check_revenue_only_on_completed(report, events)
    check_categorical_values(report, users, events, experiments)
    check_experiment_group_consistency(report, users, experiments)
    check_date_range(report, users, events)
    check_null_rates(report, users, "users")
    check_null_rates(report, events, "events")
    check_null_rates(report, experiments, "experiments")
    check_funnel_logic(report, events)
    check_experiment_conversion_matches_events(report, experiments, events)

    print_report(report)

    if report.has_critical_failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
