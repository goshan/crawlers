#!/usr/bin/env ruby

require "redis"
require "json"
require "digest"
require "time"

# Minimal cache driver that writes listing payloads to Redis.
# Prefix for all stored keys.
KEY_PREFIX = "real_state".freeze
METRIC_PREFIX = "daily_metrics".freeze

class CacheDriver
  def initialize(redis_url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))
    @redis = Redis.new(url: redis_url)
  end

  def clear
    listing_keys = []
    redis.scan_each(match: "#{KEY_PREFIX}:*") { |key| listing_keys << key }
    redis.del(*listing_keys) unless listing_keys.empty?
  end

  def all_listings
    keys = []
    redis.scan_each(match: "#{KEY_PREFIX}:*") { |key| keys << key }
    return [] if keys.empty?

    redis.mget(keys).compact.map do |raw|
      JSON.parse(raw, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end.compact
  end

  def store_listing(url:, title:, price:, size:, completed:, location:)
    payload = {
      url: url,
      title: title,
      price: price,
      size: size,
      completed: completed,
      location: location,
      cached_at: Time.now.utc.iso8601
    }

    redis.set(cache_key(url), JSON.dump(payload))
    payload
  end

  def store_daily_metrics(date:, all_avg:, koto_avg:, kamedo_avg:, counts:)
    date_str = date.strftime("%Y_%m_%d")
    payload = {
      date: date_str,
      all_avg: all_avg,
      koto_avg: koto_avg,
      kamedo_avg: kamedo_avg,
      counts: counts,
      cached_at: Time.now.utc.iso8601
    }
    redis.set(daily_metrics_key(date_str), JSON.dump(payload))
    payload
  end

  # Fetch metrics for last 7 days (date => payload).
  def last_7_days_metrics
    today = Date.today
    (0..6).map { |i| today - i }.reverse.filter_map do |date|
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

  def cache_key(url)
    "#{KEY_PREFIX}:#{Digest::SHA256.hexdigest(url)}"
  end

  def daily_metrics_key(date)
    "#{METRIC_PREFIX}:#{date}"
  end
end
