# Crawlers

First personal project of AI coding via Codex, Gemini, and Claude

Monorepo containing multiple web crawlers, each in its own subdirectory.

| Folder | Description |
|--------|-------------|
| `real_state/` | Real estate monitor — crawls SUUMO (Japanese real estate site), caches daily metrics in Redis, generates trend graphs, and sends email reports |
| `nap_camp/` | Campsite booking automation — uses Ferrum (headless Chrome) to book campsites on nap-camp.com and sends email notifications |
| `the_cliff/` | Room availability checker — monitors thecliff.airhost.co via headless Chrome and sends email when a room becomes available |

Shared dependencies are managed at the root level (`Gemfile`, `vendor/`).

