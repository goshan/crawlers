#!/usr/bin/env ruby
# One-shot migration script: Redis → MySQL
#
# Setup:
#   cd migration && bundle install
#
# Usage:
#   REDIS_URL=redis://127.0.0.1:6379/0 \
#   MYSQL_HOST=127.0.0.1 MYSQL_PORT=3306 \
#   MYSQL_DATABASE=real_state MYSQL_USER=root MYSQL_PASS= \
#   bundle exec ruby migrate_redis_to_mysql.rb

require "bundler/setup"
require "redis"
require "mysql2"
require "json"
require "date"

# ---------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------

redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))

db = Mysql2::Client.new(
  host:     ENV.fetch("MYSQL_HOST",     "127.0.0.1"),
  port:     ENV.fetch("MYSQL_PORT",     "3306").to_i,
  database: ENV.fetch("MYSQL_DATABASE", "real_state"),
  username: ENV.fetch("MYSQL_USER",     "root"),
  password: ENV.fetch("MYSQL_PASS",     ""),
  encoding: "utf8mb4"
)

# ---------------------------------------------------------------------------
# Scan all daily_metrics:* keys from Redis
# ---------------------------------------------------------------------------

keys = []
cursor = "0"
loop do
  cursor, batch = redis.scan(cursor, match: "daily_metrics:*", count: 100)
  keys.concat(batch)
  break if cursor == "0"
end

puts "Found #{keys.size} Redis keys to migrate."
exit if keys.empty?

# ---------------------------------------------------------------------------
# Prepare MySQL insert
# ---------------------------------------------------------------------------

stmt = db.prepare(<<~SQL)
  INSERT INTO daily_metrics (location_code, date, average, count)
  VALUES (?, ?, ?, ?)
  ON DUPLICATE KEY UPDATE average = VALUES(average), count = VALUES(count)
SQL

# ---------------------------------------------------------------------------
# Migrate
# ---------------------------------------------------------------------------

migrated = 0
skipped  = 0

keys.sort.each do |redis_key|
  raw = redis.get(redis_key)
  unless raw
    puts "  SKIP #{redis_key} — empty value"
    skipped += 1
    next
  end

  payload = JSON.parse(raw, symbolize_names: true)
  date    = Date.strptime(payload[:date], "%Y_%m_%d")
  avgs    = payload[:avgs]   || {}
  counts  = payload[:counts] || {}

  avgs.each do |location_code, average|
    count = counts[location_code]
    stmt.execute(location_code.to_s, date, average, count)
    migrated += 1
  end

  puts "  OK #{redis_key} → #{date} (#{avgs.size} locations)"
rescue JSON::ParserError => e
  puts "  SKIP #{redis_key} — invalid JSON: #{e.message}"
  skipped += 1
rescue => e
  puts "  ERROR #{redis_key} — #{e.message}"
  skipped += 1
end

puts "\nDone. Migrated #{migrated} rows, skipped #{skipped} keys."
