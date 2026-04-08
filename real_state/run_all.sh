#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# init rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

echo "-----------------execution on $(date '+%Y-%m-%d')-----------------"

# Run crawler (fetches listings, stores metrics)
bundle exec ruby "$SCRIPT_DIR/crawler.rb"

# Send Slack notification
#bundle exec ruby "$SCRIPT_DIR/send_slack_notification.rb"

echo "Done."
