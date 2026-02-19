#!/usr/bin/env ruby
require "net/smtp"
require "json"
require "securerandom"
require_relative "config"

RESULT_FILE = File.expand_path("last_result.json", __dir__)
MAX_ATTACHMENTS = 5

def build_email(to:, from:, subject:, body:)
  boundary = "BOUNDARY-#{SecureRandom.hex(8)}"
  parts = []

  parts << <<~HEAD
  From: #{from}
  To: #{to}
  Subject: #{subject}
  MIME-Version: 1.0
  Content-Type: multipart/mixed; boundary="#{boundary}"

  --#{boundary}
  Content-Type: text/html; charset="UTF-8"
  Content-Transfer-Encoding: 7bit

  #{body}

  HEAD

  parts << "--#{boundary}--\r\n"
  parts.join
end

# ── Load result ──────────────────────────────────────────────────────────────

unless File.exist?(RESULT_FILE)
  puts "No booking result found at #{RESULT_FILE}"
  exit 0
end

result = JSON.parse(File.read(RESULT_FILE))

# Only send email for actionable statuses
unless %w[success error].include?(result["status"])
  puts "Status '#{result["status"]}' — skipping email"
  exit 0
end

# ── Build body ───────────────────────────────────────────────────────────────

status_label = {
  "success" => "BOOKING CONFIRMED",
  "error" => "ERROR"
}

body = <<~BODY
<pre>
nap-camp Booking Result: #{status_label[result["status"]]}

Plan:      #{result["plan_name"] || "N/A"}
Check-in:  #{result["check_in"] || "N/A"}
Check-out: #{result["check_out"] || "N/A"}
Timestamp: #{result["timestamp"]}

Message: #{result["message"]}
#{result["status"] == "success" ? "\nCampsite: <a href=\"#{Config.campsite_url}\">#{Config.campsite_url}</a>" : ""}
</pre>
BODY

# ── Rehearsal mode ───────────────────────────────────────────────────────────

if Config.smtp_rehearsal
  puts body
  puts "\n(Rehearsal mode — no email sent. Configure SMTP to send.)"
  exit 0
end

# ── Collect screenshots ──────────────────────────────────────────────────────

attachments = if Dir.exist?(SCREENSHOT_DIR)
  Dir.glob(File.join(SCREENSHOT_DIR, "*.png"))
     .sort_by { |f| File.mtime(f) }
     .last(MAX_ATTACHMENTS)
else
  []
end

# ── Send email ───────────────────────────────────────────────────────────────

email = build_email(
  to: Config.smtp_to,
  from: Config.smtp_from,
  subject: "nap-camp Booking #{result["status"].upcase} #{Time.now.strftime('%Y-%m-%d')}",
  body: body,
  attachments: attachments
)

Net::SMTP.start(Config.smtp_host, Config.smtp_port, "localhost", Config.smtp_user, Config.smtp_pass, :plain) do |smtp|
  smtp.send_message(email, Config.smtp_from, [Config.smtp_to])
end

puts "Email sent to #{Config.smtp_to}"
