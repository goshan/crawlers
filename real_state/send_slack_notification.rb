#!/usr/bin/env ruby
require "net/http"
require "json"
require "date"
require_relative "./metrics_store"
require File.expand_path('../config', __FILE__)

def format_number(number)
  num_groups = number.to_s.chars.to_a.reverse.each_slice(3)
  num_groups.map(&:join).join(',').reverse
end

metrics = MetricsStore.new.today_metrics

lines = ["*Real State Metrics (Average price/size) — #{metrics[:date].strftime('%Y-%m-%d')}*"]
Config::LOCATION_CONFIG.each do |key, name|
  avg   = format_number(metrics.dig(:metrics, key, :avg).to_i)
  count = format_number(metrics.dig(:metrics, key, :count))
  lines << "• #{name}: #{avg} 円/㎡  (#{count} items)"
end
message = lines.join("\n")

if Config.slack_rehearsal
  puts message
  exit
end

uri = URI(Config.slack_webhook_url)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = (uri.scheme == "https")
req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
req.body = JSON.dump({ text: message })
res = http.request(req)

puts "Slack notification sent (HTTP #{res.code})"
