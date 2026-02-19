#!/usr/bin/env ruby
require "net/smtp"
require "json"
require "time"
require "securerandom"
require_relative "./cache_driver"
require File.expand_path('../config', __FILE__)



GRAPH_DIR = File.expand_path("graphs", __dir__)

# Build a MIME attachment part for PNGs.
def attach_file(path, boundary)
  data = File.binread(path)
  encoded = [data].pack("m0") # base64
  filename = File.basename(path)
  <<~PART
  --#{boundary}
  Content-Type: image/png; name="#{filename}"
  Content-Transfer-Encoding: base64
  Content-Disposition: attachment; filename="#{filename}"

  #{encoded}

  PART
end

def format_number(number)
  num_groups = number.to_s.chars.to_a.reverse.each_slice(3)
  num_groups.map(&:join).join(',').reverse
end

# Assemble the email with text + attachments.
def build_email(to:, from:, subject:, body:, attachments:)
  boundary = "BOUNDARY-#{SecureRandom.hex(8)}"
  parts = []

  parts << <<~HEAD
  From: #{from}
  To: #{to}
  Subject: #{subject}
  MIME-Version: 1.0
  Content-Type: multipart/mixed; boundary="#{boundary}"

  --#{boundary}
  Content-Type: text/plain; charset="UTF-8"
  Content-Transfer-Encoding: 7bit

  #{body}

  HEAD

  attachments.each do |path|
    parts << attach_file(path, boundary)
  end

  parts << "--#{boundary}--\r\n"
  parts.join
end

metrics = CacheDriver.new.today_metrics
body = "Metrics (Average price/size) for #{metrics[:date]}:\n"
Config::LOCATION_CONFIG.each do |key, config|
  body += "- #{config[:label]}: #{format_number(metrics.dig(:avgs, key).to_i)} (#{format_number(metrics.dig(:counts, key))} items)\n"
end

if Config.smtp_rehearsal
  puts body
  exit
end

attachments = %w[price_size_trend.png].map do |name|
  path = File.join(GRAPH_DIR, name)
  File.exist?(path) ? path : nil
end.compact

email = build_email(
  to: Config.smtp_to,
  from: Config.smtp_from,
  subject: "Real State Metrics #{Date.today.strftime('%Y-%m-%d')}",
  body: body,
  attachments: attachments
)

Net::SMTP.start(Config.smtp_host, Config.smtp_port, "localhost", Config.smtp_user, Config.smtp_pass, :plain) do |smtp|
  smtp.send_message(email, Config.smtp_from, [Config.smtp_to])
end

puts "Email sent to #{Config.smtp_to}"
