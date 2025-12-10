#!/usr/bin/env bash
set -euo pipefail

# --- Required environment variables (set values before running) ---
export SMTP_HOST="smtp.gmail.com"
export SMTP_USER=""
export SMTP_PASS=""
export SMTP_TO=""
# Crawler target URL (required)
export URL="https://suumo.jp/jj/bukken/ichiran/JJ012FC001/?ar=030&bs=011&ta=13&sc=13103&sc=13113&sc=13108&sc=13109&sc=13110&sc=13112&cn=9999999&cnb=0&et=9999999&hb=0&ht=9999999&kb=1&kj=9&km=1&kt=9999999&mb=0&mt=9999999&ni=9999999&pc=100&pj=1&po=0&tb=0&tj=0&tt=9999999"
# Quiet mode for crawler (1 to suppress per-listing output)
export QUIET_MODE="1"
export SLEEP_SECONDS="10"
export REQUESTS_PER_SLEEP="10" 

echo "-----------------execution on $(date '+%Y-%m-%d')-----------------"

# Run crawler (fetches listings, stores metrics)
bundle exec ruby crawler.rb

# Generate graphs (SVG + PNG)
bundle exec ruby trend_graphs.rb

# Send metrics email
bundle exec ruby send_metrics_email.rb

echo "Done."
