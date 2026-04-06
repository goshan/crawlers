# Redis → MySQL Migration

One-shot script to migrate `real_state` daily metrics from Redis to MySQL.

## Prerequisites

- Ruby (same version as the main project)
- Access to the source Redis instance
- Access to the target MySQL instance with tables already created (`db_init.rb` must have been run)

## Setup

```bash
cd real_state/migration
bundle install --path vendor/bundle
```

## Usage

```bash
REDIS_URL=redis://127.0.0.1:6379/0 \
MYSQL_HOST=127.0.0.1 \
MYSQL_PORT=3306 \
MYSQL_DATABASE=real_state \
MYSQL_USER=root \
MYSQL_PASS=secret \
bundle exec ruby migrate_redis_to_mysql.rb
```

All environment variables have defaults for local development except `MYSQL_PASS` which defaults to an empty string.

| Variable | Default | Description |
|---|---|---|
| `REDIS_URL` | `redis://127.0.0.1:6379/0` | Redis connection URL |
| `MYSQL_HOST` | `127.0.0.1` | MySQL host |
| `MYSQL_PORT` | `3306` | MySQL port |
| `MYSQL_DATABASE` | `real_state` | Target database name |
| `MYSQL_USER` | `root` | MySQL username |
| `MYSQL_PASS` | _(empty)_ | MySQL password |

## What It Does

1. Scans all `daily_metrics:*` keys from Redis using cursor-based `SCAN` (safe for production, avoids blocking `KEYS *`)
2. Parses each JSON payload and converts the date format from `YYYY_MM_DD` to a native `DATE`
3. Inserts one MySQL row per location per day using `ON DUPLICATE KEY UPDATE` — safe to re-run without creating duplicates
4. Prints each key as `OK`, `SKIP`, or `ERROR` with a final summary of migrated and skipped counts

## Sample Output

```
Found 42 Redis keys to migrate.
  OK daily_metrics:2025_01_01 → 2025-01-01 (7 locations)
  OK daily_metrics:2025_01_02 → 2025-01-02 (7 locations)
  SKIP daily_metrics:2025_01_03 — invalid JSON: ...
  ...
Done. Migrated 280 rows, skipped 1 keys.
```

## After Migration

Verify row counts in MySQL:

```sql
SELECT COUNT(*) FROM daily_metrics;
SELECT COUNT(DISTINCT date) FROM daily_metrics;
SELECT location_code, COUNT(*) FROM daily_metrics GROUP BY location_code;
```

Once confirmed, this `migration/` folder can be deleted.
