#!/usr/bin/env ruby

require "mysql2"
require File.expand_path('../config', __FILE__)

class MetricsStore
  LOCATION_KEYS = Config::LOCATION_CONFIG.keys.freeze

  def initialize
    @db = Mysql2::Client.new(Config.mysql)
  end

  def store_daily_metrics(date:, location_key:, average:, count:)
    stmt = @db.prepare(<<~SQL)
      INSERT INTO daily_metrics (location_code, date, average, count)
      VALUES (?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE average = VALUES(average), count = VALUES(count)
    SQL
    stmt.execute(location_key.to_s, date, average, count)

    { date: date, location_code: location_key, average: average, count: count }
  end

  # Fetch metrics for today.
  def today_metrics
    payload = fetch_metrics_for(Date.today)
    raise "No metrics for today" unless payload
    payload
  end

  def fetch_metrics_for(date)
    rows = @db.prepare("SELECT * FROM daily_metrics WHERE date = ?").execute(date).to_a
    return nil if rows.empty?

    metrics = rows.each_with_object({}) do |row, h|
      key    = row["location_code"].to_sym
      h[key] = { avg: row["average"]&.to_f, count: row["count"]&.to_i }
    end
    { date: date, metrics: metrics }
  end


end
