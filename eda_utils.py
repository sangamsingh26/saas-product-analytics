"""Shared helpers for the Phase 3 exploratory-analysis notebook suite.

Every notebook under ``notebooks/`` imports from this module rather than
redefining chart styling, data loading, or statistical helpers locally —
so the six notebooks read as one consistent analytical system instead of
six independently-styled reports.

This module does not touch anything from Phase 1 (data generation) or
Phase 2 (SQL analytics); it is purely additive Phase 3 infrastructure.
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.figure import Figure
from scipy import stats

# ---------------------------------------------------------------------------
# Palette: a validated, colour-blind-safe categorical palette with a fixed
# hue order, plus sequential/diverging ramps built from the same system, so
# every chart in the notebook suite draws from one consistent source.
# ---------------------------------------------------------------------------
PALETTE: list[str] = [
    "#2a78d6", "#008300", "#e87ba4", "#eda100",
    "#1baf7a", "#eb6834", "#4a3aa7", "#e34948",
]
INK = "#0b0b0b"
INK_SECONDARY = "#52514e"
INK_MUTED = "#898781"
GRID_COLOR = "#e1e0d9"
AXIS_COLOR = "#c3c2b7"
SURFACE = "#fcfcfb"
COLOR_GOOD = "#0ca30c"
COLOR_CRITICAL = "#d03b3b"
COLOR_CONTROL = PALETTE[0]
COLOR_TREATMENT = PALETTE[5]

BLUE_SEQUENTIAL = LinearSegmentedColormap.from_list(
    "brand_blue", ["#cde2fb", "#6da7ec", "#2a78d6", "#184f95", "#0d366b"]
)
DIVERGING = LinearSegmentedColormap.from_list(
    "brand_diverging", ["#0d366b", "#f0efec", "#d03b3b"]
)


def set_notebook_style() -> None:
    """Apply the shared chart chrome. Call once at the top of each notebook."""
    import seaborn as sns

    sns.set_theme(style="whitegrid", rc={"axes.facecolor": SURFACE, "figure.facecolor": SURFACE})
    plt.rcParams.update({
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "savefig.facecolor": SURFACE,
        "font.family": ["Segoe UI", "DejaVu Sans", "sans-serif"],
        "font.size": 10,
        "text.color": INK,
        "axes.edgecolor": AXIS_COLOR,
        "axes.labelcolor": INK_SECONDARY,
        "axes.grid": True,
        "grid.color": GRID_COLOR,
        "grid.linewidth": 0.9,
        "xtick.color": INK_SECONDARY,
        "ytick.color": INK_SECONDARY,
    })


def style_axis(ax: plt.Axes, title: str, xlabel: str = "", ylabel: str = "", grid_axis: str = "y") -> plt.Axes:
    """Apply the notebook suite's shared chart chrome to a single axes."""
    ax.set_title(title, fontsize=13, fontweight="bold", color=INK, pad=14, loc="left")
    ax.set_xlabel(xlabel, fontsize=10)
    ax.set_ylabel(ylabel, fontsize=10)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_color(AXIS_COLOR)
    ax.spines["bottom"].set_color(AXIS_COLOR)
    ax.tick_params(labelsize=9)
    if grid_axis:
        ax.grid(axis=grid_axis, color=GRID_COLOR, linewidth=0.9, zorder=0)
    else:
        ax.grid(False)
    ax.set_axisbelow(True)
    return ax


def annotate_bars(
    ax: plt.Axes,
    bars,
    fmt: str = "{:,.0f}",
    offset: int = 3,
    fontsize: float = 8.5,
    horizontal: bool = False,
) -> None:
    """Add a value label above (vertical bars) or beside (horizontal bars) each bar."""
    for bar in bars:
        if horizontal:
            width = bar.get_width()
            ax.annotate(fmt.format(width), xy=(width, bar.get_y() + bar.get_height() / 2),
                        xytext=(offset, 0), textcoords="offset points",
                        ha="left", va="center", fontsize=fontsize, color=INK_SECONDARY)
        else:
            height = bar.get_height()
            ax.annotate(fmt.format(height), xy=(bar.get_x() + bar.get_width() / 2, height),
                        xytext=(0, offset), textcoords="offset points",
                        ha="center", va="bottom", fontsize=fontsize, color=INK_SECONDARY)


def build_color_map(categories: Iterable[str]) -> dict[str, str]:
    """Assign a fixed palette slot to each category, in sorted (stable) order."""
    return dict(zip(sorted(set(categories)), PALETTE))


def pct(numerator: float, denominator: float) -> float:
    """Safe percentage helper."""
    return 100.0 * numerator / denominator if denominator else 0.0


def save_fig(fig: Figure, name: str, images_dir: Path) -> Path:
    """Save a figure as a publication-quality PNG under images_dir and return its path."""
    images_dir.mkdir(parents=True, exist_ok=True)
    out_path = images_dir / f"{name}.png"
    fig.savefig(out_path, dpi=150, bbox_inches="tight", facecolor=SURFACE)
    return out_path


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------
def load_datasets(data_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Load users, events, and experiments CSVs with parsed date columns."""
    users = pd.read_csv(data_dir / "users.csv", parse_dates=["signup_date"])
    events = pd.read_csv(data_dir / "events.csv", parse_dates=["event_time", "event_date"])
    experiments = pd.read_csv(data_dir / "experiments.csv", parse_dates=["exposure_date", "conversion_date"])
    return users, events, experiments


# ---------------------------------------------------------------------------
# Retention
# ---------------------------------------------------------------------------
def compute_retention_flags(
    users_df: pd.DataFrame, events_df: pd.DataFrame, day_offsets: tuple[int, ...] = (1, 7, 30)
) -> pd.DataFrame:
    """Return one row per user with a 0/1 flag for activity on each exact day offset from signup."""
    activity = events_df[["user_id", "event_date"]].drop_duplicates().merge(
        users_df[["user_id", "signup_date"]], on="user_id", how="inner"
    )
    activity["days_since_signup"] = (activity["event_date"] - activity["signup_date"]).dt.days

    flags = users_df[["user_id"]].copy()
    for day in day_offsets:
        active_ids = set(activity.loc[activity["days_since_signup"] == day, "user_id"])
        flags[f"retained_day{day}"] = flags["user_id"].isin(active_ids).astype(int)
    return flags


def retention_curve(users_df: pd.DataFrame, events_df: pd.DataFrame, max_day: int = 60) -> pd.Series:
    """Return % of users active on each exact day offset 0..max_day since signup."""
    activity = events_df[["user_id", "event_date"]].drop_duplicates().merge(
        users_df[["user_id", "signup_date"]], on="user_id", how="inner"
    )
    activity["days_since_signup"] = (activity["event_date"] - activity["signup_date"]).dt.days
    activity = activity[(activity["days_since_signup"] >= 0) & (activity["days_since_signup"] <= max_day)]

    total_users = len(users_df)
    daily_active = activity.groupby("days_since_signup")["user_id"].nunique()
    return (daily_active.reindex(range(0, max_day + 1), fill_value=0) / total_users * 100)


# ---------------------------------------------------------------------------
# Funnel
# ---------------------------------------------------------------------------
FUNNEL_STAGES = ["Signup", "Search Started", "Booking Started", "Booking Completed"]
FUNNEL_EVENT_NAMES = ["search_started", "booking_started", "booking_completed"]


def compute_funnel(users_df: pd.DataFrame, events_df: pd.DataFrame, subset_user_ids: set | None = None) -> pd.DataFrame:
    """Compute lifetime funnel-stage user counts, conversion %, and drop-off %."""
    if subset_user_ids is not None:
        users_df = users_df[users_df["user_id"].isin(subset_user_ids)]
        events_df = events_df[events_df["user_id"].isin(subset_user_ids)]

    stage_user_sets = [set(users_df["user_id"])] + [
        set(events_df.loc[events_df["event_name"] == name, "user_id"]) for name in FUNNEL_EVENT_NAMES
    ]
    funnel_df = pd.DataFrame({"stage": FUNNEL_STAGES, "users": [len(s) for s in stage_user_sets]})
    funnel_df["pct_of_signups"] = funnel_df["users"] / funnel_df["users"].iloc[0] * 100
    funnel_df["pct_of_previous_stage"] = funnel_df["users"] / funnel_df["users"].shift(1) * 100
    funnel_df["drop_off_pct"] = 100 - funnel_df["pct_of_previous_stage"]
    return funnel_df


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------
def wald_ci(successes: float, n: float, z: float = 1.96) -> tuple[float, float, float]:
    """Wald 95% confidence interval for a proportion. Returns (p, ci_low, ci_high)."""
    p = successes / n
    se = np.sqrt(p * (1 - p) / n)
    return p, p - z * se, p + z * se


def mean_ci(series: pd.Series, z: float = 1.96) -> tuple[float, float, float]:
    """Normal-approximation 95% confidence interval for a sample mean."""
    n = len(series)
    mean = series.mean()
    sem = series.std(ddof=1) / np.sqrt(n)
    return mean, mean - z * sem, mean + z * sem


def two_proportion_ztest(conv_a: float, n_a: float, conv_b: float, n_b: float) -> tuple[float, float]:
    """Two-proportion z-test. Returns (z_statistic, two_tailed_p_value)."""
    p_a, p_b = conv_a / n_a, conv_b / n_b
    p_pool = (conv_a + conv_b) / (n_a + n_b)
    se_pool = np.sqrt(p_pool * (1 - p_pool) * (1 / n_a + 1 / n_b))
    z_stat = (p_b - p_a) / se_pool
    p_value = 2 * (1 - stats.norm.cdf(abs(z_stat)))
    return z_stat, p_value


def welch_ttest(sample_a: pd.Series, sample_b: pd.Series) -> tuple[float, float]:
    """Welch's two-sample t-test (unequal variances). Returns (t_statistic, p_value)."""
    result = stats.ttest_ind(sample_b, sample_a, equal_var=False)
    return float(result.statistic), float(result.pvalue)


def significance_label(p_value: float) -> str:
    """Human-readable significance verdict from a p-value."""
    if p_value < 0.01:
        return "Significant at 99% confidence (p < 0.01)"
    if p_value < 0.05:
        return "Significant at 95% confidence (p < 0.05)"
    if p_value < 0.10:
        return "Significant at 90% confidence (p < 0.10)"
    return "Not statistically significant (p >= 0.10)"
