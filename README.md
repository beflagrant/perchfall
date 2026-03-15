# Perchfall

Synthetic browser monitoring via Playwright. Give it a URL; get back a structured, immutable Ruby report.

**Framework-agnostic** — no Rails, no ActiveRecord, no persistence. Works from a Rails app, a Rake task, a Sidekiq job, or a plain Ruby script.

---

## Requirements

| Dependency | Version |
|---|---|
| Ruby | ≥ 3.2 |
| Node | ≥ 18 (for `node:util` `parseArgs`) |
| Playwright | installed via npm in the project or globally |

Install Playwright browsers once:

```sh
npm install playwright
npx playwright install chromium
```

---

## Installation

Add to your `Gemfile`:

```ruby
gem "perchfall"
```

Or install directly:

```sh
gem install perchfall
```

---

## Quick start

```ruby
require "perchfall"

report = Perchfall.run(url: "https://example.com")

report.ok?           # => true
report.http_status   # => 200
report.duration_ms   # => 834
report.network_errors  # => []   (Array<Perchfall::NetworkError>)
report.console_errors  # => []   (Array<Perchfall::ConsoleError>)
report.to_json       # => '{"status":"ok","url":"https://example.com",...}'
```

---

## Options

```ruby
report = Perchfall.run(
  url:           "https://example.com",   # required
  timeout_ms:    10_000,                  # default: 30_000
  scenario_name: "homepage_smoke"         # optional label, included in report
)
```

---

## JSON report schema

```json
{
  "status":        "ok",
  "url":           "https://example.com",
  "scenario_name": "homepage_smoke",
  "timestamp":     "2026-03-15T21:30:00Z",
  "ok":            true,
  "http_status":   200,
  "duration_ms":   834,
  "network_errors": [
    {
      "url":     "https://example.com/assets/app.js",
      "method":  "GET",
      "failure": "HTTP 404"
    }
  ],
  "console_errors": [
    {
      "type":     "error",
      "text":     "Uncaught ReferenceError: foo is not defined",
      "location": "https://example.com/assets/app.js:10:5"
    }
  ],
  "error": null
}
```

When the page itself fails to load, `status` is `"error"`, `ok` is `false`, `http_status` is `null`, and `error` contains the Playwright error message.

---

## Error handling

Perchfall distinguishes between three failure modes:

```ruby
begin
  report = Perchfall.run(url: "https://example.com", timeout_ms: 10_000)

rescue Perchfall::Errors::PageLoadError => e
  # The page could not be loaded (timeout, DNS failure, etc.).
  # A partial report is still available.
  puts "Page failed: #{e.message}"
  store_report(e.report.to_json)          # partial data is still useful

rescue Perchfall::Errors::ScriptError => e
  # The Node script ran but exited non-zero (unexpected crash).
  puts "Script crashed (exit #{e.exit_status})"
  puts e.stderr

rescue Perchfall::Errors::InvocationError => e
  # Node could not be started at all (not installed, wrong path).
  puts "Cannot run Node: #{e.message}"

rescue Perchfall::Errors::ParseError => e
  # The script produced output that wasn't valid JSON.
  puts "Bad output: #{e.message}"

rescue Perchfall::Errors::Error => e
  # Catch-all for any other Perchfall error.
end
```

**Important:** `network_errors` and `console_errors` on the report are not exceptions. A page can load successfully (`ok: true`, `http_status: 200`) while still having broken sub-resources or JS errors — these are captured in the arrays for you to analyze downstream.

---

## Advanced usage

### Custom timeout and scenario name

```ruby
client = Perchfall::Client.new
report = client.run(
  url:           "https://example.com/checkout",
  timeout_ms:    15_000,
  scenario_name: "checkout_smoke"
)
```

### Injecting a custom invoker

For testing, or to plug in an alternative runner (e.g., a remote Playwright service):

```ruby
client = Perchfall::Client.new(invoker: MyRemotePlaywrightInvoker.new)
report = client.run(url: "https://example.com")
```

---

## Using from a Rails app

The gem does not depend on Rails. The recommended pattern is a background job that calls Perchfall, then persists the resulting JSON.

### Example: Sidekiq job

```ruby
# app/jobs/synthetic_check_job.rb
class SyntheticCheckJob
  include Sidekiq::Job

  def perform(url, scenario_name = nil)
    report = Perchfall.run(url: url, scenario_name: scenario_name)
    SyntheticResult.create!(
      url:           report.url,
      scenario_name: report.scenario_name,
      ok:            report.ok?,
      http_status:   report.http_status,
      duration_ms:   report.duration_ms,
      payload:       report.to_json,   # store the full JSON blob
      checked_at:    report.timestamp
    )
  rescue Perchfall::Errors::PageLoadError => e
    SyntheticResult.create!(
      url:       e.report.url,
      ok:        false,
      payload:   e.report.to_json,
      checked_at: e.report.timestamp
    )
    # Re-raise or handle alerting separately
  end
end
```

### Example: ActiveRecord model (migration sketch)

```ruby
create_table :synthetic_results do |t|
  t.string   :url,           null: false
  t.string   :scenario_name
  t.boolean  :ok,            null: false
  t.integer  :http_status
  t.integer  :duration_ms
  t.jsonb    :payload,       null: false   # full Perchfall JSON
  t.datetime :checked_at,    null: false
  t.timestamps
end
```

Then in a Rails initializer, schedule checks via your job queue:

```ruby
# config/initializers/synthetic_checks.rb
SYNTHETIC_TARGETS = [
  { url: "https://example.com",         scenario_name: "homepage"  },
  { url: "https://example.com/sign_in", scenario_name: "sign_in"   },
].freeze
```

---

## Development

```sh
bundle install
bundle exec rspec          # run all specs
bundle exec rake           # same (default task)
bin/console                # interactive IRB session with perchfall loaded
```

The Node script lives at `playwright/check.js`. You can run it directly:

```sh
node playwright/check.js --url https://example.com --timeout 10000
```

---

## Architecture

```
Perchfall.run(url:)
  └─ Client#run
       └─ PlaywrightInvoker#run
            ├─ CommandRunner#call          # wraps Open3, injectable
            └─ Parsers::PlaywrightJsonParser#parse
                 └─ Report (immutable value object)
                      ├─ NetworkError (Data.define)
                      └─ ConsoleError (Data.define)
```

Every collaborator is injected via the constructor — nothing reaches out for its own dependencies. This makes every class unit-testable with plain Ruby doubles and no process spawning.

---

## License

MIT
