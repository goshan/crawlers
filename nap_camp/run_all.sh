#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# init rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

echo "-----------------nap-camp booking on $(date '+%Y-%m-%d %H:%M:%S')-----------------"

# Run booking crawler
bundle exec ruby "$SCRIPT_DIR/crawler.rb"

# Send email notification
bundle exec ruby "$SCRIPT_DIR/send_booking_email.rb"

echo "Done."
