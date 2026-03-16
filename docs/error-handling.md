# Error handling

Perchfall uses a typed exception hierarchy. Rescue the most specific class you care about, or catch everything at the base class.

## Exception reference

| Exception | When raised | What to do |
| --- | --- | --- |
| `ArgumentError` | URL fails validation (bad scheme, internal address) | Fix the URL before calling again |
| `Perchfall::Errors::PageLoadError` | Page could not load (timeout, DNS failure, HTTP error) | A partial report is attached; log or store it |
| `Perchfall::Errors::ConcurrencyLimitError` | All browser slots are occupied and the wait timeout expired | Back off and retry later |
| `Perchfall::Errors::InvocationError` | Node could not be started (not installed, wrong PATH) | Check your Node installation |
| `Perchfall::Errors::ScriptError` | Node script ran but exited non-zero (unexpected crash) | Check Node and Playwright versions |
| `Perchfall::Errors::ParseError` | Node script produced output that isn't valid JSON | File a bug report |
| `Perchfall::Errors::Error` | Base class — catches any Perchfall error | Use as a catch-all |

## Example

```ruby
begin
  report = Perchfall.run(url: "https://example.com", timeout_ms: 10_000)

rescue Perchfall::Errors::PageLoadError => e
  # A partial report is always attached — capture what was collected.
  puts "Page failed: #{e.message}"
  store_report(e.report.to_json)

rescue Perchfall::Errors::ConcurrencyLimitError
  # Back off and retry later.
  retry_job_in(30.seconds)

rescue Perchfall::Errors::InvocationError => e
  # Node isn't available on this machine.
  alert_ops("Perchfall: #{e.message}")

rescue ArgumentError => e
  # Bad URL — fix the caller.
  Rails.logger.error("Invalid URL passed to Perchfall: #{e.message}")

rescue Perchfall::Errors::Error => e
  # Unexpected Perchfall error.
  Sentry.capture_exception(e)
end
```

## `PageLoadError` and partial reports

When Playwright can't finish loading a page, Perchfall raises `PageLoadError` rather than returning a report. The exception always carries a partial `report` with whatever was collected before the failure — network errors, console errors, and timing data may all be present. Always store it.

```ruby
rescue Perchfall::Errors::PageLoadError => e
  e.report.ok?            # => false
  e.report.network_errors # => may contain errors collected before failure
  e.report.to_json        # => storable JSON
```
