#!/usr/bin/env ruby
# One-time database initialisation script.
# Run once per environment to create tables and seed the locations master table.
# Usage: bundle exec ruby real_state/db_init.rb

require "mysql2"
require File.expand_path('../config', __FILE__)

db = Mysql2::Client.new(Config.mysql)

db.query(<<~SQL)
  CREATE TABLE IF NOT EXISTS locations (
    code  VARCHAR(64)  NOT NULL PRIMARY KEY,
    label VARCHAR(255) NOT NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
SQL
puts "Table 'locations' ready."

db.query(<<~SQL)
  CREATE TABLE IF NOT EXISTS daily_metrics (
    id            INT         NOT NULL AUTO_INCREMENT PRIMARY KEY,
    location_code VARCHAR(64) NOT NULL,
    date          DATE        NOT NULL,
    average       DOUBLE,
    count         INT,
    created_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_location_date (location_code, date),
    CONSTRAINT fk_location FOREIGN KEY (location_code) REFERENCES locations(code)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
SQL
puts "Table 'daily_metrics' ready."

stmt = db.prepare("INSERT INTO locations (code, label) VALUES (?, ?) ON DUPLICATE KEY UPDATE label = VALUES(label)")
Config::LOCATION_CONFIG.each do |key, name|
  stmt.execute(key.to_s, name)
end
puts "Locations synced (#{Config::LOCATION_CONFIG.size} entries)."
