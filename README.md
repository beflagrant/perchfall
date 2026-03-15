# Perchfall

Synthetic browser monitoring via Playwright. Give it a URL; get back a structured, immutable Ruby report.

**Framework-agnostic** — no Rails, no ActiveRecord, no persistence. Works from a Rails app, a Rake task, a Sidekiq job, or a plain Ruby script.

---

## Requirements

| Dependency | Version |
| --- | --- |
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

report.ok?             # => true
report.http_status     # => 200
report.duration_ms     # => 834
report.network_errors  # => []   (Array<Perchfall::NetworkError>)
report.console_errors  # => []   (Array<Perchfall::ConsoleError>)
report.to_json         # => '{"status":"ok","url":"https://example.com",...}'
```

---

## Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `url` | String | — | **Required.** Must be `http` or `https`. |
| `timeout_ms` | Integer | `30_000` | Playwright navigation timeout. |
| `wait_until` | String | `"load"` | When to consider navigation complete. See below. |
| `scenario_name` | String | `nil` | Optional label included in the report. |

### `wait_until` strategies

| Value | When it fires |
| --- | --- |
| `"load"` | Page `load` event — HTML, images, and subresources. **Default.** |
| `"domcontentloaded"` | DOM parsed; faster but subresources may still be loading. |
| `"networkidle"` | No network connections for 500ms. Avoid for sites with WebSockets or analytics — they never go idle. |
| `"commit"` | Navigation response received; fastest but minimal. |

```ruby
report = Perchfall.run(
  url:           "https://example.com",
  timeout_ms:    10_000,
  wait_until:    "domcontentloaded",
  scenario_name: "homepage_smoke"
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

When the page itself fails to load, `status` is `"error"`, `ok` is `false`, `http_status` is `null`, and `error` contains the Playwright error message. `network_errors` and `console_errors` are always arrays — even on failure — because Playwright may have captured some before the failure occurred.

---

## Error handling

Perchfall uses a typed exception hierarchy. Rescue the most specific class you care about:

```ruby
begin
  report = Perchfall.run(url: "https://example.com", timeout_ms: 10_000)

rescue Perchfall::Errors::PageLoadError => e
  # The page could not be loaded (timeout, DNS failure, etc.).
  # A partial report is always available on the exception.
  puts "Page failed: #{e.message}"
  store_report(e.report.to_json)

rescue Perchfall::Errors::ConcurrencyLimitError => e
  # All browser slots are occupied and the timeout expired.
  # Back off and retry later.
  puts "Too many concurrent checks: #{e.message}"

rescue Perchfall::Errors::ScriptError => e
  # The Node script ran but exited non-zero (unexpected crash).
  puts "Script crashed (exit #{e.exit_status}): #{e.stderr}"

rescue Perchfall::Errors::InvocationError => e
  # Node could not be started at all (not installed, wrong path, etc.).
  puts "Cannot run Node: #{e.message}"

rescue Perchfall::Errors::ParseError => e
  # The script produced output that wasn't valid JSON.
  puts "Bad output: #{e.message}"

rescue ArgumentError => e
  # The URL failed validation (bad scheme, internal address, etc.).
  puts "Invalid URL: #{e.message}"

rescue Perchfall::Errors::Error => e
  # Catch-all for any other Perchfall error.
end
```

**Note:** `network_errors` and `console_errors` on the report are not exceptions. A page can load successfully (`ok: true`) while still having broken sub-resources or JS errors — these are captured in the arrays for downstream analysis.

---

## URL validation

Perchfall validates URLs before spawning any process:

- **Scheme** must be `http` or `https`. `file://`, `ftp://`, `javascript:`, `data:`, and bare strings are rejected with `ArgumentError`.
- **Host** must not be a known internal address. The following are blocked: `localhost`, `127.0.0.0/8`, `::1`, `169.254.0.0/16` (including the AWS metadata endpoint), `fe80::/10`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, and `0.0.0.0/8`.

> **Note:** A public DNS name that resolves to a private IP is not blocked at the application layer. Network-level egress filtering on the host running Chromium is the correct defence for that case.

---

## Concurrency limiting

Perchfall caps the number of simultaneous Chromium instances at **5 by default**, process-wide. Callers beyond the cap block until a slot opens or the timeout expires.

```ruby
# Default: 5 concurrent browsers, 30s wait timeout
Perchfall.run(url: "https://example.com")

# Custom limit at Client construction
client = Perchfall::Client.new(
  limiter: Perchfall::ConcurrencyLimiter.new(limit: 2, timeout_ms: 10_000)
)
```

When the cap is reached and the timeout expires, `Perchfall::Errors::ConcurrencyLimitError` is raised. Set `timeout_ms` on the limiter to a value less than or equal to your job queue's own timeout to avoid thread exhaustion.

> **Note:** The limit is per-process. For distributed rate limiting across multiple workers, use a Redis semaphore or similar mechanism outside this gem.

---

## Advanced usage

### Injecting a custom invoker

For testing, or to plug in an alternative runner (e.g. a remote Playwright service):

```ruby
client = Perchfall::Client.new(invoker: MyRemotePlaywrightInvoker.new)
report = client.run(url: "https://example.com")
```

### Running the Node script directly

```sh
node playwright/check.js --url https://example.com --timeout 10000 --wait-until load
```

Output is a single JSON object on stdout. Exit 0 means the JSON is trustworthy (check `status` inside it). Exit 1 means the script itself crashed and stdout cannot be trusted.

---

## Using from a Rails app

The gem does not depend on Rails. The recommended pattern is a background job that calls Perchfall and persists the resulting JSON.

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
      payload:       report.to_json,
      checked_at:    report.timestamp
    )
  rescue Perchfall::Errors::PageLoadError => e
    SyntheticResult.create!(
      url:        e.report.url,
      ok:         false,
      payload:    e.report.to_json,
      checked_at: e.report.timestamp
    )
  end
end
```

### Example: ActiveRecord migration

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

---

## CI / CD

### Unit suite (automatic)

The Ruby unit suite runs on every push to `main` and every pull request via GitHub Actions. It requires no browser or Node — the full suite runs in under a second using `FakeCommandRunner`.

```
.github/workflows/ci.yml
```

### Playwright smoke check (manual)

A second workflow lets you run a real browser check against any URL directly from the GitHub Actions UI:

#### Actions → Playwright smoke check → Run workflow

| Input | Default | Description |
| --- | --- | --- |
| `url` | `https://example.com` | URL to check |
| `scenario_name` | *(blank)* | Optional label in the report JSON |
| `wait_until` | `load` | Navigation strategy (dropdown) |
| `timeout_ms` | `30000` | Playwright timeout in ms |

The job installs Ruby, Node 20, and Chromium, runs the check, and prints the full JSON report to the Actions log. Exit codes:

| Code | Meaning |
| --- | --- |
| `0` | Page loaded, `ok: true` |
| `1` | Page loaded but `ok: false` (DNS failure, timeout, etc.) |
| `2` | Gem-level error (Node not found, parse failure, etc.) |

```
.github/workflows/playwright.yml
```

---

## Development

```sh
bundle install
bundle exec rspec    # run all specs (~0.4s, no browser required)
bundle exec rake     # same (default task)
bin/console          # IRB session with perchfall loaded
```

---

## Architecture

```
Perchfall.run(url:)
  └─ Client#run
       ├─ UrlValidator#validate!       # scheme + host allowlist
       ├─ ConcurrencyLimiter#acquire   # caps parallel browser processes
       └─ PlaywrightInvoker#run
            ├─ CommandRunner#call      # wraps Open3, injectable
            └─ PlaywrightJsonParser#parse
                 └─ Report (immutable value object)
                      ├─ NetworkError (Data.define)
                      └─ ConsoleError (Data.define)
```

Every collaborator is injected via the constructor — nothing reaches out for its own dependencies. The full test suite runs without a browser, Node, or network.

Architecture decisions are documented in [`doc/adr/`](doc/adr/).

---

## License

MIT
