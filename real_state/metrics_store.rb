#!/usr/bin/env ruby

require "sqlite3"
require "date"
require "time"
require File.expand_path('../config', __FILE__)

class MetricsStore
  LOCATION_KEYS = Config::LOCATION_CONFIG.keys.freeze

  def initialize(db_path: Config.db_path)
    @db = SQLite3::Database.new(db_path)
    @db.results_as_hash = true
    setup_schema
  end

  def store_daily_metrics(date:, location_key:, average:, count:)
    date_str   = date.strftime("%Y-%m-%d")
    created_at = Time.now.utc.iso8601

    @db.execute(
      "INSERT OR REPLACE INTO daily_metrics (location_key, date, average, count, created_at) VALUES (?, ?, ?, ?, ?)",
      [location_key.to_s, date_str, average, count, created_at]
    )

    { date: date_str, location_key: location_key, average: average, count: count, created_at: created_at }
  end

  # Fetch metrics for today.
  def today_metrics
    payload = fetch_metrics_for(Date.today)
    raise "No metrics for today" unless payload
    payload
  end

  def fetch_metrics_for(date)
    date_str = date.strftime("%Y-%m-%d")
    rows = @db.execute("SELECT * FROM daily_metrics WHERE date = ?", [date_str])
    return nil if rows.empty?

    metrics = rows.each_with_object({}) do |row, h|
      key    = row["location_key"].to_sym
      h[key] = { avg: row["average"]&.to_f, count: row["count"]&.to_i }
    end
    { date: date_str, metrics: metrics }
  end

  private

  def setup_schema
    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS locations (
        key   TEXT PRIMARY KEY,
        label TEXT NOT NULL
      )
    SQL

    @db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS daily_metrics (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        location_key TEXT NOT NULL REFERENCES locations(key),
        date         TEXT NOT NULL,
        average      REAL,
        count        INTEGER,
        created_at   TEXT NOT NULL,
        UNIQUE (location_key, date)
      )
    SQL

    Config::LOCATION_CONFIG.each do |key, name|
      @db.execute(
        "INSERT OR IGNORE INTO locations (key, label) VALUES (?, ?)",
        [key.to_s, name]
      )
    end
  end
end
