-- =============================================================================
-- 00_schema.sql
-- Purpose : Data Definition Language (DDL) for the SQLite analytics database.
--           Defines the three base tables that mirror data/raw/*.csv and the
--           indexes used by the analysis queries in 01-10.
-- Engine  : SQLite 3.35+
-- Loaded by: src/build_database.py (drops and recreates the database, then
--            executes this file before loading CSV rows).
-- =============================================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS experiments;
DROP TABLE IF EXISTS users;

-- -----------------------------------------------------------------------------
-- users: one row per registered user (grain = user_id)
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    user_id             TEXT PRIMARY KEY,
    signup_date         TEXT NOT NULL,      -- ISO date  YYYY-MM-DD
    country             TEXT NOT NULL,
    city                TEXT NOT NULL,
    platform            TEXT NOT NULL,      -- iOS | Android | Web
    acquisition_channel TEXT NOT NULL,
    age_group           TEXT,               -- nullable: user declined to state
    experiment_group    TEXT NOT NULL,      -- control | treatment
    first_device_type   TEXT NOT NULL
);

-- -----------------------------------------------------------------------------
-- events: one row per behavioural event (grain = event_id)
-- -----------------------------------------------------------------------------
CREATE TABLE events (
    event_id          TEXT PRIMARY KEY,
    user_id           TEXT NOT NULL REFERENCES users (user_id),
    event_time        TEXT NOT NULL,        -- ISO datetime YYYY-MM-DD HH:MM:SS
    event_date        TEXT NOT NULL,        -- ISO date, denormalised for fast daily grouping
    session_id        TEXT NOT NULL,
    event_name        TEXT NOT NULL,
    product_area      TEXT NOT NULL,
    device_type       TEXT NOT NULL,
    revenue           REAL,                 -- populated only for booking_completed
    ride_distance_km  REAL,                 -- populated only for booking-related events
    payment_method    TEXT                  -- populated only for payment-related events
);

-- -----------------------------------------------------------------------------
-- experiments: one row per user, outcome of the simplified_booking_flow test
-- -----------------------------------------------------------------------------
CREATE TABLE experiments (
    user_id             TEXT PRIMARY KEY REFERENCES users (user_id),
    experiment_name     TEXT NOT NULL,
    experiment_group    TEXT NOT NULL,      -- control | treatment
    exposure_date       TEXT NOT NULL,
    converted           INTEGER NOT NULL,   -- 0 / 1 boolean
    conversion_date     TEXT,               -- null if not converted
    days_to_conversion  INTEGER             -- null if not converted
);

-- -----------------------------------------------------------------------------
-- Indexes to support the analysis queries (joins/filters on these columns)
-- -----------------------------------------------------------------------------
CREATE INDEX idx_events_user_id            ON events (user_id);
CREATE INDEX idx_events_event_name         ON events (event_name);
CREATE INDEX idx_events_event_date         ON events (event_date);
CREATE INDEX idx_events_session_id         ON events (session_id);
CREATE INDEX idx_events_user_event_name    ON events (user_id, event_name);

CREATE INDEX idx_users_country   ON users (country);
CREATE INDEX idx_users_platform  ON users (platform);
CREATE INDEX idx_users_channel   ON users (acquisition_channel);
CREATE INDEX idx_users_signup    ON users (signup_date);

CREATE INDEX idx_experiments_group ON experiments (experiment_group);
