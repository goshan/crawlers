#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# init rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

echo "-----------------the-cliff check on $(date '+%Y-%m-%d %H:%M:%S')-----------------"

# Run availability checker
bundle exec ruby "$SCRIPT_DIR/crawler.rb"

# Send email notification if available
bundle exec ruby "$SCRIPT_DIR/send_notification_email.rb"

echo "Done."
