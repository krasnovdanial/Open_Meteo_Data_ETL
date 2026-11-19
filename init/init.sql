CREATE SCHEMA IF NOT EXISTS raw_weather;

CREATE TABLE IF NOT EXISTS raw_weather.hourly_observations (
    city VARCHAR(64) NOT NULL,
    latitude NUMERIC(8, 4) NOT NULL,
    longitude NUMERIC(8, 4) NOT NULL,
    measured_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    temperature_c NUMERIC(5, 2),
    humidity_pct NUMERIC(5, 2),
    precipitation_mm NUMERIC(6, 2),
    wind_speed_kmh NUMERIC(6, 2),
    heat_index_c NUMERIC(5, 2),
    loaded_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_hourly_observations PRIMARY KEY (city, measured_at)
);

CREATE INDEX IF NOT EXISTS idx_hourly_obs_measured_at
    ON raw_weather.hourly_observations (measured_at);