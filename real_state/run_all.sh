#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# init rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

echo "-----------------execution on $(date '+%Y-%m-%d')-----------------"

# Run crawler (fetches listings, stores metrics)
bundle exec ruby "$SCRIPT_DIR/crawler.rb"

# Generate graphs (SVG + PNG)
bundle exec ruby "$SCRIPT_DIR/trend_graphs.rb"

# Send metrics email
bundle exec ruby "$SCRIPT_DIR/send_metrics_email.rb"

echo "Done."
