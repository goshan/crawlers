#!/usr/bin/env ruby
require "net/smtp"
require "json"
require "time"
require "securerandom"
require_relative "./cache_driver"

# ---- Config: set these or export as env vars ----
SMTP_HOST = ENV.fetch("SMTP_HOST")
SMTP_PORT = ENV.fetch("SMTP_PORT", "587").to_i
SMTP_USER = ENV.fetch("SMTP_USER")
SMTP_PASS = ENV.fetch("SMTP_PASS")
FROM      = ENV.fetch("SMTP_FROM", SMTP_USER)
TO        = ENV.fetch("SMTP_TO")
# -------------------------------------------------

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
body = <<~TEXT
Metrics for #{metrics[:date]}:
- Average price/size (all): #{format_number(metrics[:all_avg].to_i)} (#{format_number(metrics.dig(:counts, :all))} items)
- Average price/size (江東区): #{format_number(metrics[:koto_avg].to_i)} (#{format_number(metrics.dig(:counts, :koto))} items)
- Average price/size (亀戸): #{format_number(metrics[:kamedo_avg].to_i)} (#{format_number(metrics.dig(:counts, :kamedo))} items)
TEXT

attachments = %w[all_trend.png koto_trend.png kameido_trend.png].map do |name|
  path = File.join(GRAPH_DIR, name)
  File.exist?(path) ? path : nil
end.compact

email = build_email(
  to: TO,
  from: FROM,
  subject: "Real State Metrics #{Time.now.utc.strftime('%Y-%m-%d')}",
  body: body,
  attachments: attachments
)

Net::SMTP.start(SMTP_HOST, SMTP_PORT, "localhost", SMTP_USER, SMTP_PASS, :plain) do |smtp|
  smtp.send_message(email, FROM, [TO])
end

puts "Email sent to #{TO}"
