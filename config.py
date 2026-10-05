"""Central configuration for synthetic data generation.

All tunable parameters for dataset size, date ranges, file paths, and
generation randomness live here so that generate_data.py and
validate_data.py stay in sync and reproducible.
"""

from pathlib import Path
from datetime import date

# ---------------------------------------------------------------------------
# Reproducibility
# ---------------------------------------------------------------------------
RANDOM_SEED: int = 42

# ---------------------------------------------------------------------------
# Volume parameters
# ---------------------------------------------------------------------------
NUM_USERS: int = 5_000
MIN_EVENTS: int = 120_000
MAX_EVENTS: int = 180_000

# ---------------------------------------------------------------------------
# Date range (must cover at least 12 months)
# ---------------------------------------------------------------------------
START_DATE: date = date(2024, 1, 1)
END_DATE: date = date(2025, 6, 30)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
PROJECT_ROOT: Path = Path(__file__).resolve().parent.parent
DATA_RAW_DIR: Path = PROJECT_ROOT / "data" / "raw"
DATA_PROCESSED_DIR: Path = PROJECT_ROOT / "data" / "processed"

USERS_FILE: Path = DATA_RAW_DIR / "users.csv"
EVENTS_FILE: Path = DATA_RAW_DIR / "events.csv"
EXPERIMENTS_FILE: Path = DATA_RAW_DIR / "experiments.csv"

SQL_DIR: Path = PROJECT_ROOT / "sql"
SCHEMA_FILE: Path = SQL_DIR / "00_schema.sql"
DATABASE_FILE: Path = DATA_PROCESSED_DIR / "analytics.db"

# ---------------------------------------------------------------------------
# Categorical domains
# ---------------------------------------------------------------------------
COUNTRIES = ["Germany", "Austria", "Spain", "Netherlands", "France"]

COUNTRY_CITIES = {
    "Germany": ["Berlin", "Hamburg", "Munich"],
    "Austria": ["Vienna"],
    "Spain": ["Barcelona", "Madrid"],
    "Netherlands": ["Amsterdam"],
    "France": ["Paris"],
}

PLATFORMS = ["iOS", "Android", "Web"]
PLATFORM_WEIGHTS = [0.45, 0.42, 0.13]

ACQUISITION_CHANNELS = [
    "Organic",
    "Paid Search",
    "Paid Social",
    "Referral",
    "Partnership",
    "Direct",
]
ACQUISITION_CHANNEL_WEIGHTS = [0.28, 0.22, 0.18, 0.14, 0.10, 0.08]

AGE_GROUPS = ["18-24", "25-34", "35-44", "45-54", "55+"]
AGE_GROUP_WEIGHTS = [0.22, 0.34, 0.24, 0.13, 0.07]

EXPERIMENT_GROUPS = ["control", "treatment"]

DEVICE_TYPES = ["iOS", "Android", "Web"]

# ---------------------------------------------------------------------------
# Event taxonomy
# ---------------------------------------------------------------------------
EVENT_NAMES = [
    "app_open",
    "signup_completed",
    "location_permission_granted",
    "search_started",
    "search_completed",
    "ride_option_viewed",
    "promo_viewed",
    "booking_started",
    "booking_completed",
    "booking_cancelled",
    "favourite_location_added",
    "notification_enabled",
    "support_contacted",
    "payment_failed",
    "rating_submitted",
]

EVENT_PRODUCT_AREA = {
    "app_open": "Engagement",
    "signup_completed": "Onboarding",
    "location_permission_granted": "Onboarding",
    "search_started": "Search",
    "search_completed": "Search",
    "ride_option_viewed": "Search",
    "promo_viewed": "Engagement",
    "booking_started": "Booking",
    "booking_completed": "Booking",
    "booking_cancelled": "Booking",
    "favourite_location_added": "Engagement",
    "notification_enabled": "Engagement",
    "support_contacted": "Support",
    "payment_failed": "Payments",
    "rating_submitted": "Engagement",
}

PRODUCT_AREAS = ["Onboarding", "Search", "Booking", "Payments", "Engagement", "Support"]

PAYMENT_METHODS = ["Card", "PayPal", "Apple Pay", "Google Pay", "Cash", "None"]

# ---------------------------------------------------------------------------
# Experiment configuration
# ---------------------------------------------------------------------------
EXPERIMENT_NAME: str = "simplified_booking_flow"
CONTROL_CONVERSION_RATE: float = 0.24
TREATMENT_CONVERSION_UPLIFT: float = 0.035  # absolute uplift over control

# ---------------------------------------------------------------------------
# Business logic thresholds
# ---------------------------------------------------------------------------
ACTIVATION_WINDOW_DAYS: int = 7
CHURN_INACTIVITY_DAYS: int = 30
RETENTION_CHECKPOINTS_DAYS = [1, 7, 30]

# Revenue distribution for completed bookings (EUR)
REVENUE_MEAN: float = 14.50
REVENUE_STD: float = 6.0
REVENUE_MIN: float = 3.5
REVENUE_MAX: float = 65.0

# Ride distance distribution (km)
RIDE_DISTANCE_MEAN: float = 6.2
RIDE_DISTANCE_STD: float = 4.0
RIDE_DISTANCE_MIN: float = 0.4
RIDE_DISTANCE_MAX: float = 45.0
