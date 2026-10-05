"""Run a .sql file against the project's SQLite database and print results.

Splits the file into individual statements and executes them in order.
SELECT/WITH statements have their results printed as a table (truncated
to a preview of rows for readability); DDL/DML statements are executed
silently. Useful for exploring the analysis queries in ``sql/`` directly
from the command line.

Usage:
    python src/run_sql.py sql/03_kpi_dashboard.sql
    python src/run_sql.py sql/03_kpi_dashboard.sql --max-rows 30
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

import pandas as pd

import config


def _has_executable_content(statement: str) -> bool:
    """True if the statement has SQL beyond comments/whitespace."""
    for line in statement.splitlines():
        line = line.strip()
        if line and not line.startswith("--"):
            return True
    return False


def split_statements(sql_text: str) -> list[str]:
    """Split a SQL script into individual, non-empty statements."""
    statements = [s.strip() for s in sql_text.split(";")]
    return [s for s in statements if s and _has_executable_content(s)]


def run_file(path: Path, max_rows: int) -> None:
    """Execute every statement in ``path`` against the analytics database."""
    if not config.DATABASE_FILE.exists():
        print(
            f"ERROR: database not found at {config.DATABASE_FILE}. "
            "Run 'python src/build_database.py' first.",
            file=sys.stderr,
        )
        sys.exit(1)

    sql_text = path.read_text(encoding="utf-8")
    statements = split_statements(sql_text)
    conn = sqlite3.connect(config.DATABASE_FILE)

    query_num = 0
    try:
        for statement in statements:
            code_lines = [
                line for line in statement.splitlines()
                if line.strip() and not line.strip().startswith("--")
            ]
            first_word = code_lines[0].strip().split(None, 1)[0].upper() if code_lines else ""
            if first_word in ("SELECT", "WITH"):
                query_num += 1
                print(f"\n{'=' * 70}\nQuery {query_num}\n{'=' * 70}")
                df = pd.read_sql_query(statement, conn)
                with pd.option_context("display.max_columns", None, "display.width", 160):
                    print(df.head(max_rows).to_string(index=False))
                print(f"({len(df)} row(s) returned)")
            else:
                conn.execute(statement)
        conn.commit()
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sql_file", type=Path, help="Path to a .sql file")
    parser.add_argument("--max-rows", type=int, default=20, help="Max rows to print per query")
    args = parser.parse_args()
    run_file(args.sql_file, args.max_rows)


if __name__ == "__main__":
    main()
