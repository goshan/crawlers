# Real State Monitor

Tools to crawl SUUMO listings, cache results to Redis, generate trend graphs, and email daily metrics.

## Setup
```bash
bundle install
```
- Install ImageMagick (required by Gruff for graph generation). On macOS with Homebrew:
  ```bash
  brew install imagemagick
  ```

## Environment Variables
- `URL` (required; start URL for the crawler)
- `MAX_PAGE` (optional; positive integer to limit pagination, default or <=0 for all)
- `SAMPLING_RATE` (optional; fraction of listings to sample per page, default `1.0`)
- `REQUESTS_PER_SLEEP` (optional; number of requests before sleeping, default `10`)
- `SLEEP_SECONDS` (optional; seconds to sleep after each request window, default `10`)
- `QUIET_MODE` (`1` to suppress per-listing output from `crawler.rb`)
- `REDIS_URL` (default: `redis://127.0.0.1:6379/0`)
- SMTP (required for email):
  - `SMTP_HOST`
  - `SMTP_PORT` (e.g., `587`)
  - `SMTP_USER`
  - `SMTP_PASS` (for Gmail, use an App Password)
  - `SMTP_FROM` (defaults to `SMTP_USER` if unset)
  - `SMTP_TO`

## Commands
- Run crawler (requires `URL`):  
  ```bash
  URL="https://example.com/path" MAX_PAGE=3 SAMPLING_RATE=0.5 QUIET_MODE=1 bundle exec ruby crawler.rb
  ```
- Generate graphs (SVG + PNG in `graphs/`):  
  ```bash
  bundle exec ruby trend_graphs.rb
  ```
- Send metrics email (requires SMTP vars + Redis metrics + graphs present):  
  ```bash
  bundle exec ruby send_metrics_email.rb
  ```
- Run everything in sequence (set env vars in the script first):  
  ```bash
  ./run_all.sh
  ```

## Notes
- Crawler stores listings and daily metrics in Redis with prefixes `real_state:*` and `daily_metrics:YYYY_MM_DD`.
- Graphs are generated from the last 7 days of metrics.
