# CLAUDE.md

## Project Overview

Monorepo containing multiple web crawlers, each in its own subdirectory.

| Folder | Description |
|--------|-------------|
| `real_state/` | Real estate monitor — crawls SUUMO (Japanese real estate site), stores daily metrics in MySQL, and sends Slack reports |
| `nap_camp/` | Campsite booking automation — uses Ferrum (headless Chrome) to book campsites on nap-camp.com and sends email notifications |
| `the_cliff/` | Room availability checker — monitors thecliff.airhost.co via headless Chrome and sends email when a room becomes available |

Shared dependencies are managed at the root level (`Gemfile`, `vendor/`).

---

## real_state/

### Tech Stack

- **Language:** Ruby
- **Web Scraping:** Mechanize + Nokogiri
- **Storage:** MySQL (via `mysql2` gem)
- **Notifications:** Slack incoming webhook
- **Text Encoding:** NKF for Japanese character handling

### Architecture

Two-stage pipeline: **Crawl → Notify**

```
crawler.rb → metrics_store.rb → send_slack_notification.rb
```

Orchestrated by `run_all.sh`.

### File Map

| File | Purpose |
|------|---------|
| `real_state/crawler.rb` | Scrapes SUUMO listings, extracts prices/sizes, computes per-sqm ratios, stores in MySQL |
| `real_state/config.rb` | Configuration module with env-aware loading, type coercion, defaults, and `LOCATION_CONFIG` |
| `real_state/metrics_store.rb` | MySQL read/write layer (`store_daily_metrics`, `fetch_metrics_for`, etc.) |
| `real_state/db_init.rb` | One-time setup script — creates `locations` and `daily_metrics` tables and seeds location master data; run once per environment before first crawler run |
| `real_state/send_slack_notification.rb` | Reads today's metrics from MySQL and posts a formatted message to Slack; supports rehearsal mode |
| `real_state/run_all.sh` | Runs crawler → Slack notification in sequence |
| `real_state/config/development.rb` | Dev config (1 page, no throttling, local MySQL) |
| `real_state/config/production.rb` | Prod config (rate limiting, MySQL + Slack credentials from ENV) |

### Commands

```bash
# Install dependencies
bundle install

# One-time DB setup (run once per environment before first crawler run)
bundle exec ruby real_state/db_init.rb

# Run individual components
bundle exec ruby real_state/crawler.rb
bundle exec ruby real_state/send_slack_notification.rb

# Run full pipeline
./real_state/run_all.sh

# Production mode
APP_ENV=production \
  MYSQL_HOST=x MYSQL_USER=x MYSQL_PASS=x MYSQL_DATABASE=x \
  SLACK_WEBHOOK_URL=x \
  ./real_state/run_all.sh
```

### Configuration

- `APP_ENV` controls which config file loads from `real_state/config/` (default: `development`)
- Config files return a Ruby hash and are loaded via `eval`
- Key settings: `start_url`, `max_page`, `sampling_rate`, `sleep_seconds`, `requests_per_sleep`, `max_retry`, `quiet_mode`, MySQL connection keys, `slack_webhook_url`
- Location categories are defined in `Config::LOCATION_CONFIG` as a flat `symbol => Japanese name` map

### External Dependencies

- **MySQL** must be running and accessible — connection configured via `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASS`, `MYSQL_DATABASE`

### Key Patterns

- **Rate limiting:** Configurable sleep intervals and requests-per-window to avoid overwhelming SUUMO
- **Retry logic:** Configurable `max_retry` with backoff for failed HTTP requests
- **Price extraction:** Multi-strategy parser (hidden inputs → table cells → regex) to handle varied SUUMO page layouts
- **Location categorization:** Properties matched to categories by address string matching; always includes "all"
- **Rehearsal mode:** Slack notification prints to stdout when `SLACK_WEBHOOK_URL` is not set

### Adding a New Location

Add an entry to `LOCATION_CONFIG` in `real_state/config.rb`:

```ruby
LOCATION_CONFIG = {
  all:      { label: "全体",  layer: :all  },
  # ... existing locations ...
  your_key: { label: "地名",  layer: :area }
}.freeze
```

| Field | Description |
|-------|-------------|
| key (e.g. `your_key`) | A unique Ruby symbol — used as `location_key` in MySQL and as the Slack label key |
| `label` | Japanese location string used for **address matching** — the crawler checks if a property's `所在地` (address) field contains this string |
| `layer` | Granularity level: `:all` (the catch-all aggregate), `:city` (ward/city level, e.g. 江東区), `:area` (neighbourhood within a city, e.g. 亀戸) |

No other files need changes. The crawler, metrics store, and Slack notifier all iterate over `LOCATION_CONFIG` dynamically.

After editing `LOCATION_CONFIG`, re-run `db_init.rb` to sync the `locations` master table:

```bash
bundle exec ruby real_state/db_init.rb
```

This is safe to re-run at any time — it uses upsert so existing rows are untouched, new locations are inserted, and renamed labels/layers are updated.

> **Existing installs:** if you already have a `locations` table without the `layer` column, `db_init.rb` will not add it automatically. Run this migration manually once:
> ```sql
> ALTER TABLE locations ADD COLUMN layer ENUM('all', 'city', 'area') NOT NULL DEFAULT 'area';
> ```

> **Removing a location:** cannot be automated — the FK constraint on `daily_metrics` prevents deleting a location that has historical rows. To remove one, first delete or reassign its `daily_metrics` rows manually, then delete the row from `locations`.

---

## nap_camp/ (In Developing)

### Tech Stack

- **Language:** Ruby
- **Browser Automation:** Ferrum (headless Chrome via CDP) — required because nap-camp.com is a Next.js/React SPA
- **Email:** Net::SMTP with MIME multipart (same pattern as `real_state/`)

### Architecture

Two-stage pipeline: **Book → Notify**

```
crawler.rb → send_booking_email.rb
```

Orchestrated by `run_all.sh`. The crawler writes `last_result.json` which the email script reads.

### File Map

| File | Purpose |
|------|---------|
| `nap_camp/crawler.rb` | Automates login, plan selection, date picking, and booking on nap-camp.com using headless Chrome |
| `nap_camp/config.rb` | Configuration module with env-aware loading (same pattern as `real_state/config.rb`) |
| `nap_camp/send_booking_email.rb` | Reads booking result JSON, builds MIME email with screenshots attached |
| `nap_camp/run_all.sh` | Cleans old screenshots, runs crawler, then sends email |
| `nap_camp/config/development.rb` | Dev config: `dry_run: true`, `headless: false` for visual debugging |
| `nap_camp/config/production.rb` | Prod config: credentials from ENV, `headless: true` |

### Commands

```bash
# Run in development (visible browser, stops before booking)
NAP_CAMP_EMAIL=x NAP_CAMP_PASSWORD=y bundle exec ruby nap_camp/crawler.rb

# Run full pipeline
NAP_CAMP_EMAIL=x NAP_CAMP_PASSWORD=y ./nap_camp/run_all.sh

# Production mode
APP_ENV=production NAP_CAMP_EMAIL=x NAP_CAMP_PASSWORD=y \
  NAP_CAMP_CHECK_IN=2025-08-01 NAP_CAMP_CHECK_OUT=2025-08-02 \
  SMTP_USER=x SMTP_PASS=y SMTP_TO=z \
  ./nap_camp/run_all.sh
```

### Configuration

- `APP_ENV` controls which config file loads (default: `development`)
- Key settings: `campsite_url`, `login_url`, `book_url`, `email`, `password`, `target_plan_name`, `check_in_date`, `check_out_date`, `headless`, `timeout`, SMTP credentials
- `headless: false` shows the browser window for debugging (default in development)

### External Dependencies

- **Google Chrome** (or Chromium) must be installed — Ferrum drives it via CDP

### Key Patterns

- **Text-based element finding:** CSS class names in the React SPA are hashed/unstable, so elements are found by visible text content via JS evaluation
- **Wait-for-render:** Polls for elements with timeout after every navigation/click to handle async React renders
- **Rehearsal mode:** Email prints to stdout when SMTP is not configured

---

## the_cliff/

### Tech Stack

- **Language:** Ruby
- **Browser Automation:** Ferrum (headless Chrome via CDP) — required because thecliff.airhost.co is a React SPA on the Airhost platform
- **Email:** Net::SMTP with MIME multipart (same pattern as `nap_camp/`)

### Architecture

Two-stage pipeline: **Check → Notify**

```
crawler.rb → send_notification_email.rb
```

Orchestrated by `run_all.sh`. The crawler writes `last_result.json` which the email script reads.

### File Map

| File | Purpose |
|------|---------|
| `the_cliff/crawler.rb` | Navigates to the house page with date query params, evaluates available room count from the DOM, writes result JSON |
| `the_cliff/config.rb` | Configuration module with env-aware loading (same pattern as `nap_camp/config.rb`) |
| `the_cliff/send_notification_email.rb` | Reads result JSON, sends email for `available` and `not_found` statuses |
| `the_cliff/run_all.sh` | rbenv-aware orchestration: runs crawler then email script |
| `the_cliff/config/development.rb` | Dev config: hardcoded dates, `headless: false` |
| `the_cliff/config/production.rb` | Prod config: dates and SMTP from ENV, `headless: true` |

### Commands

```bash
# Development (visible browser)
bundle exec ruby the_cliff/crawler.rb

# Full pipeline
./the_cliff/run_all.sh

# Production
APP_ENV=production \
  CLIFF_CHECK_IN=2026-03-21 CLIFF_CHECK_OUT=2026-03-22 \
  SMTP_USER=x SMTP_PASS=y SMTP_TO=z \
  ./the_cliff/run_all.sh
```

### Configuration

- `APP_ENV` controls which config file loads (default: `development`)
- Key settings: `house_url`, `check_in_date`, `check_out_date`, `num_rooms`, `headless`, `timeout`, SMTP credentials
- Production ENV vars: `CLIFF_HOUSE_URL`, `CLIFF_CHECK_IN`, `CLIFF_CHECK_OUT`, `CLIFF_NUM_ROOMS`, `SMTP_USER`, `SMTP_PASS`, `SMTP_TO`

### Result Statuses

| Status | Meaning | Email sent? |
|--------|---------|-------------|
| `available` | Enough rooms available for the requested dates | Yes |
| `not_found` | Room item not found — page structure may have changed | Yes |
| `not_enough` | Room exists but fewer slots than `num_rooms` | No |
| `sold_out` | Room is fully booked | No |
| `error` | Unhandled exception | No |

### Key Patterns

- **Integer return from JS:** Availability check returns `-1` (not found), `0` (sold out), or `N` (count of enabled `<select>` options) — avoids string parsing in Ruby
- **Rehearsal mode:** Email prints to stdout when SMTP is not configured

---

## No Test Suite

There are currently no automated tests in this project.
