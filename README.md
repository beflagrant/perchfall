# Perchfall

[![CI](https://github.com/beflagrant/perchfall/actions/workflows/ci.yml/badge.svg)](https://github.com/beflagrant/perchfall/actions/workflows/ci.yml)
[![Playwright smoke check](https://github.com/beflagrant/perchfall/actions/workflows/playwright.yml/badge.svg)](https://github.com/beflagrant/perchfall/actions/workflows/playwright.yml)
[![Gem Version](https://badge.fury.io/rb/perchfall.svg)](https://badge.fury.io/rb/perchfall)

**Synthetic browser monitoring for Ruby.** Give it a URL; get back a structured report of what a real Chromium browser saw — HTTP status, broken assets, JavaScript errors, and load time. No framework required.

```ruby
report = Perchfall.run(url: "https://example.com")

report.ok?             # => true
report.http_status     # => 200
report.duration_ms     # => 834
report.network_errors  # => []
report.console_errors  # => []
report.to_json         # => '{"status":"ok","url":"https://example.com",...}'
```

---

## Why Perchfall

**Uptime monitoring tells you a server is responding. Perchfall tells you the page actually works.**

- A `200 OK` doesn't mean your JavaScript loaded.
- An APM trace doesn't capture a missing CDN asset.
- A health check endpoint doesn't know your checkout flow is broken.

Perchfall runs a headless Chromium browser against your URL and gives you back everything it found: the HTTP status, every failed network request, every JavaScript error logged to the console, and how long it took. The result is an **immutable Ruby value object** you can store, log, or alert on — no database schema imposed, no framework lock-in.

Drop it into a Sidekiq job, a Rake task, a CI step, or a plain Ruby script. It works anywhere Ruby runs.

---

## Requirements

| Dependency | Version |
| --- | --- |
| Ruby | ≥ 3.2 |
| Node | ≥ 18 |
| Playwright | installed via npm |

---

## Installation

```sh
# 1. Add the gem
bundle add perchfall

# 2. Install Playwright (once per machine)
npm install playwright
npx playwright install chromium
```

---

## Quickstart

```ruby
require "perchfall"

report = Perchfall.run(url: "https://example.com")

if report.ok?
  puts "#{report.url} loaded in #{report.duration_ms}ms"
else
  puts "Page failed: #{report.network_errors.map(&:failure).join(", ")}"
end
```

### Detect broken assets and JS errors

```ruby
report = Perchfall.run(url: "https://example.com")

report.network_errors.each do |e|
  puts "#{e.http_method} #{e.url} — #{e.failure}"
end
# GET https://example.com/assets/app.js — HTTP 404
# GET https://cdn.example.com/font.woff — net::ERR_NAME_NOT_RESOLVED

report.console_errors.each do |e|
  puts "#{e.type}: #{e.text}"
end
# error: Uncaught ReferenceError: Stripe is not defined
```

A page can be `ok: true` (it loaded) and still have broken sub-resources. Perchfall captures both.

### Handle page load failures

```ruby
begin
  report = Perchfall.run(url: "https://example.com", timeout_ms: 10_000)
rescue Perchfall::Errors::PageLoadError => e
  # Page couldn't load at all — a partial report is always attached.
  store_report(e.report.to_json)
end
```

### Use in a background job

```ruby
class SyntheticCheckJob
  include Sidekiq::Job

  def perform(url)
    report = Perchfall.run(url: url)
    SyntheticResult.create!(ok: report.ok?, payload: report.to_json)
  rescue Perchfall::Errors::PageLoadError => e
    SyntheticResult.create!(ok: false, payload: e.report.to_json)
  end
end
```

---

## What's in a report

Every check returns a `Perchfall::Report`:

| Field | Type | Description |
| --- | --- | --- |
| `ok?` | Boolean | `true` if the page loaded successfully |
| `http_status` | Integer / nil | HTTP response code |
| `duration_ms` | Integer | Total time from navigation start to `load` event |
| `url` | String | The URL checked |
| `timestamp` | Time | When the check ran (UTC) |
| `cache_profile` | Symbol / nil | Cache profile used (`:query_bust`, `:warm`, `:no_cache`, `:no_store`) |
| `network_errors` | Array | Failed or errored network requests |
| `console_errors` | Array | JavaScript errors logged to the browser console |
| `to_json` | String | Full report as JSON |

→ [Full report schema and JSON reference](docs/report-schema.md)

---

## Errors

| Exception | When |
| --- | --- |
| `ArgumentError` | URL is invalid (bad scheme, internal address) |
| `Perchfall::Errors::PageLoadError` | Page couldn't load; partial report attached at `e.report` |
| `Perchfall::Errors::ConcurrencyLimitError` | All browser slots are busy; back off and retry |
| `Perchfall::Errors::InvocationError` | Node isn't installed or not in PATH |
| `Perchfall::Errors::Error` | Base class — catches any Perchfall error |

→ [Full error handling guide](docs/error-handling.md)

---

## Configuration

```ruby
Perchfall.run(
  url:           "https://example.com",
  timeout_ms:    10_000,             # default 30_000, max 60_000
  wait_until:    "domcontentloaded", # default "load"
  scenario_name: "homepage_smoke",   # included in report JSON
  cache_profile: :no_cache           # default :query_bust
)
```

→ [All options, cache profiles, and wait_until strategies](docs/configuration.md)

---

## Further reading

- [Rails integration — Sidekiq job, schema, scheduling](docs/rails-integration.md)
- [Security — SSRF protection, URL validation, ignore rules](docs/security.md)
- [Architecture decisions](doc/adr/)

---

## Development

```sh
bundle install
bundle exec rspec              # ~0.5s, no browser or Node required (208 examples)
RUN_JS_SPECS=true bundle exec rspec  # includes check.js integration specs (223 examples)
bin/console                    # IRB with perchfall loaded
```

---

## License

MIT
