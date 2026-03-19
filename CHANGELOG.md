# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-03-19

### Added

- `cache_profile:` option on `Perchfall.run` — replaces `bust_cache:` with four named profiles:
  - `:query_bust` (default) — appends `?_pf=<unix_timestamp>` to force a cold fetch
  - `:warm` — no URL mutation, no extra headers; measures real-user warm-cache experience
  - `:no_cache` — sets `Cache-Control: no-cache` on all requests (main document + sub-resources)
  - `:no_store` — sets `Cache-Control: no-store, no-cache` and `Pragma: no-cache`
  - Custom Hash form: `cache_profile: { headers: { "Cache-Control" => "max-age=0" } }`
- `report.cache_profile` — cache profile is stored on the `Report` and included in `to_h` / `to_json`
- `--headers` argument to `playwright/check.js` — extra HTTP headers applied via `page.setExtraHTTPHeaders`
- `check.js` integration specs (15 examples, tagged `:js`); excluded from default run, opt-in via `RUN_JS_SPECS=true`
- `check-js.yml` GitHub Actions workflow — runs automatically when `playwright/check.js` or its specs change; caches Playwright Chromium binary keyed on `package-lock.json`

### Changed

- Renamed cache-bust query parameter from `_perchfall=` to `_pf=` (shorter, less intrusive in logs)
- Validation order: `cache_profile` → `wait_until` → `timeout_ms` → URL validation — invalid params now raise before the effective URL is built
- `check.js` now writes a `status: "error"` JSON result (exit 0) for malformed or non-object `--headers` instead of crashing

### Breaking Changes

- `bust_cache:` keyword argument removed. Migrate: `bust_cache: false` → `cache_profile: :warm`; `bust_cache: true` → `cache_profile: :query_bust` (or omit — it is the default)
- Cache-bust query parameter renamed from `_perchfall=` to `_pf=` — update any log filters or URL allow-lists

### Security

- Custom `cache_profile` headers validated against a `FORBIDDEN_HEADERS` denylist (`Authorization`, `Cookie`, `Set-Cookie`, `Host`, `X-Forwarded-For`, `X-Forwarded-Host`, `X-Real-IP`) — these cannot be injected via the custom Hash form

## [0.1.0] - 2026-03-17

### Added

- `Perchfall.run(url:)` — primary public API; returns an immutable `Report` value object
- `bust_cache:` option (default `true`) appends a `_perchfall=<timestamp>` query parameter to prevent CDN and proxy caching from masking real page state; `report.url` always reflects the original caller URL, not the cache-busted one
- `scenario_name:` option included in the report for labelling checks
- `wait_until:` option (`load`, `domcontentloaded`, `networkidle`, `commit`) controls when Playwright considers navigation complete
- `timeout_ms:` option (default 30 000, max 60 000) for Playwright navigation timeout
- `Report` value object with `ok?`, `http_status`, `duration_ms`, `network_errors`, `console_errors`, `to_json`
- `ignored_network_errors` / `ignored_console_errors` on `Report` — errors suppressed by ignore rules are captured, not silently dropped
- Configurable ignore rules via `ignore:` — `IgnoreRule` supports substring, regex, and wildcard matching on URL/text and failure/type fields
- Default ignore rule suppresses `net::ERR_ABORTED` (analytics beacons, cancelled prefetches)
- Typed exception hierarchy: `PageLoadError` (with partial report), `ConcurrencyLimitError`, `InvocationError`, `ScriptError`, `ParseError`
- Process-wide concurrency limiter (default 5 simultaneous Chromium instances) using Mutex + ConditionVariable — no spinning, slot always released
- SSRF mitigations: scheme allowlist (`http`/`https` only), literal IP blocklist (loopback, link-local, RFC-1918), DNS resolution check; URL validation always runs against the effective URL sent to Playwright (post cache-bust)
- Full dependency injection throughout — test suite runs in ~0.4 s with no browser, Node, or network required
- GitHub Actions CI workflow (unit suite) and manual Playwright smoke check workflow

[Unreleased]: https://github.com/beflagrant/perchfall/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/beflagrant/perchfall/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/beflagrant/perchfall/releases/tag/v0.1.0
