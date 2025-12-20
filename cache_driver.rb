#!/usr/bin/env ruby

require "redis"
require "json"
require "digest"
require "time"

# Minimal cache driver that writes listing payloads to Redis.
# Prefix for all stored keys.
METRIC_PREFIX = "daily_metrics".freeze

class CacheDriver
  def initialize(redis_url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))
    @redis = Redis.new(url: redis_url)
  end

  def store_daily_metrics(date:, avgs:, counts:)
    date_str = date.strftime("%Y_%m_%d")
    payload = {
      date: date_str,
      avgs: avgs,
      counts: counts,
      cached_at: Time.now.utc.iso8601
    }
    redis.set(daily_metrics_key(date_str), JSON.dump(payload))
    payload
  end

  # Fetch metrics for last 30 days (date => payload).
  def last_30_days_metrics
    today = Date.today
    (0..29).map { |i| today - i }.reverse.filter_map do |date|
      payload = fetch_metrics_for(date)
      payload ? [date, payload] : nil
    end
  end

  # Fetch metrics for today.
  def today_metrics
    payload = fetch_metrics_for(Date.today)
    raise "No metrics for today" unless payload
    payload
  end

  def fetch_metrics_for(date)
    key = daily_metrics_key(date.strftime("%Y_%m_%d"))
    raw = redis.get(key)
    return nil unless raw
    JSON.parse(raw, symbolize_names: true)
  rescue JSON::ParserError
    nil
  end

  private

  attr_reader :redis

  def daily_metrics_key(date)
    "#{METRIC_PREFIX}:#{date}"
  end
end
