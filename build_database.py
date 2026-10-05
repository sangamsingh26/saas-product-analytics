"""Build a SQLite database from the generated CSV datasets.

Reads ``data/raw/users.csv``, ``data/raw/events.csv``, and
``data/raw/experiments.csv`` and loads them into
``data/processed/analytics.db`` using the schema defined in
``sql/00_schema.sql``. This database is what every query in ``sql/`` is
written and tested against.
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

import pandas as pd

import config


def create_schema(conn: sqlite3.Connection) -> None:
    """Execute the DDL script to (re)create tables and indexes."""
    schema_sql = config.SCHEMA_FILE.read_text(encoding="utf-8")
    conn.executescript(schema_sql)


def load_users(conn: sqlite3.Connection) -> int:
    """Load users.csv into the users table. Returns row count loaded."""
    df = pd.read_csv(config.USERS_FILE)
    df.to_sql("users", conn, if_exists="append", index=False)
    return len(df)


def load_events(conn: sqlite3.Connection) -> int:
    """Load events.csv into the events table. Returns row count loaded."""
    df = pd.read_csv(config.EVENTS_FILE)
    df.to_sql("events", conn, if_exists="append", index=False)
    return len(df)


def load_experiments(conn: sqlite3.Connection) -> int:
    """Load experiments.csv into the experiments table. Returns row count loaded."""
    df = pd.read_csv(config.EXPERIMENTS_FILE)
    df["converted"] = df["converted"].astype(bool).astype(int)
    df.to_sql("experiments", conn, if_exists="append", index=False)
    return len(df)


def main() -> None:
    """Rebuild the SQLite database from scratch and print load statistics."""
    try:
        config.DATA_PROCESSED_DIR.mkdir(parents=True, exist_ok=True)

        if config.DATABASE_FILE.exists():
            config.DATABASE_FILE.unlink()

        conn = sqlite3.connect(config.DATABASE_FILE)
        try:
            create_schema(conn)
            n_users = load_users(conn)
            n_events = load_events(conn)
            n_experiments = load_experiments(conn)
            conn.commit()
        finally:
            conn.close()

        print("=" * 60)
        print("SQLITE DATABASE BUILD SUMMARY")
        print("=" * 60)
        print(f"Database file: {config.DATABASE_FILE}")
        print(f"users:       {n_users:,} rows")
        print(f"events:      {n_events:,} rows")
        print(f"experiments: {n_experiments:,} rows")
        print("=" * 60)

    except Exception as exc:  # noqa: BLE001 - top-level build guard
        print(f"ERROR building database: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
