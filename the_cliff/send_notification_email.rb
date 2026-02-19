#!/usr/bin/env ruby
require "net/smtp"
require "json"
require "securerandom"
require_relative "config"

RESULT_FILE = File.expand_path("last_result.json", __dir__)

def build_email(to:, from:, subject:, body:)
  boundary = "BOUNDARY-#{SecureRandom.hex(8)}"
  <<~EMAIL
  From: #{from}
  To: #{to}
  Subject: #{subject}
  MIME-Version: 1.0
  Content-Type: multipart/mixed; boundary="#{boundary}"

  --#{boundary}
  Content-Type: text/html; charset="UTF-8"
  Content-Transfer-Encoding: 7bit

  #{body}

  --#{boundary}--
  EMAIL
end

# ── Load result ──────────────────────────────────────────────────────────────

unless File.exist?(RESULT_FILE)
  puts "No check result found at #{RESULT_FILE}"
  exit 0
end

result = JSON.parse(File.read(RESULT_FILE))

ACTIONABLE_STATUSES = %w[available not_found].freeze

unless ACTIONABLE_STATUSES.include?(result["status"])
  puts "Status '#{result["status"]}' — skipping email"
  exit 0
end

# ── Build body ───────────────────────────────────────────────────────────────

status_label = result["status"] == "available" ? "AVAILABLE" : "NOT FOUND"

url = "#{Config.house_url}?start_date=#{result["check_in"]}&end_date=#{result["check_out"]}"

body = <<~BODY
<pre>
The Cliff Room Availability: #{status_label}

Check-in:  #{result["check_in"] || "N/A"}
Check-out: #{result["check_out"] || "N/A"}
Expected:  #{result["expected"] || "N/A"}
Available: #{result["available"] || "N/A"}
Timestamp: #{result["timestamp"]}

Message: #{result["message"]}
#{result["status"] == "available" ? "\nBook now: <a href=\"#{url}\">#{url}</a>" : ""}
</pre>
BODY

subject = "The Cliff #{status_label} #{result["check_in"]}"

# ── Rehearsal mode ───────────────────────────────────────────────────────────

if Config.smtp_rehearsal
  puts body
  puts "\n(Rehearsal mode — no email sent. Configure SMTP to send.)"
  exit 0
end

# ── Send email ───────────────────────────────────────────────────────────────

email = build_email(
  to:      Config.smtp_to,
  from:    Config.smtp_from,
  subject: subject,
  body:    body
)

Net::SMTP.start(Config.smtp_host, Config.smtp_port, "localhost", Config.smtp_user, Config.smtp_pass, :plain) do |smtp|
  smtp.send_message(email, Config.smtp_from, [Config.smtp_to])
end

puts "Email sent to #{Config.smtp_to}"
