# Report schema

Every `Perchfall.run` call returns an immutable `Perchfall::Report` object.

## Ruby interface

```ruby
report = Perchfall.run(url: "https://example.com")

report.ok?             # => true / false
report.http_status     # => 200
report.duration_ms     # => 834
report.url             # => "https://example.com"
report.scenario_name   # => "homepage_smoke" (or nil)
report.timestamp       # => 2026-03-15 21:30:00 UTC (Time)
report.cache_profile   # => :query_bust (or :warm, :no_cache, :no_store, nil)
report.network_errors  # => Array<Perchfall::NetworkError>
report.console_errors  # => Array<Perchfall::ConsoleError>
report.to_json         # => JSON string (see below)
```

Ignored errors (suppressed by ignore rules) are available separately:

```ruby
report.ignored_network_errors  # => Array<Perchfall::NetworkError>
report.ignored_console_errors  # => Array<Perchfall::ConsoleError>
```

## JSON schema

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
  "error": null,
  "cache_profile": "query_bust"
}
```

When a page **fails to load**, `status` is `"error"`, `ok` is `false`, `http_status` is `null`, and `error` contains the Playwright error message. `network_errors` and `console_errors` are always arrays — Playwright may have captured some before the failure occurred.

## `network_errors` vs `ok?`

`ok?` reflects whether the page loaded at all. `network_errors` captures broken sub-resources (missing assets, failed API calls) that Playwright recorded during the load — a page can be `ok: true` and still have `network_errors`. Use both to get a complete picture of page health.
