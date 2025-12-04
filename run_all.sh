#!/usr/bin/env bash
set -euo pipefail

# --- Required environment variables (set values before running) ---
export SMTP_HOST="smtp.gmail.com"
export SMTP_USER=""
export SMTP_PASS=""
export SMTP_TO=""
# Quiet mode for crawler (1 to suppress per-listing output)
export QUIET_MODE="1"

echo "-----------------execution on $(date '+%Y-%m-%d')-----------------"

# Run crawler (fetches listings, stores metrics)
bundle exec ruby crawler.rb

# Generate graphs (SVG + PNG)
bundle exec ruby trend_graphs.rb

# Send metrics email
bundle exec ruby send_metrics_email.rb
