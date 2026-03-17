# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-03-17

### Added

- `Perchfall.run(url:)` — primary public API; returns an immutable `Report` value object
- `bust_cache:` option (default `true`) appends a `_perchfall=<timestamp>` query parameter to prevent CDN and proxy caching from masking real page state
- `scenario_name:` option included in the report for labelling checks
- `wait_until:` option (`load`, `domcontentloaded`, `networkidle`, `commit`) controls when Playwright considers navigation complete
- `timeout_ms:` option (default 30 000, max 60 000) for Playwright navigation timeout
- `Report` value object with `ok?`, `http_status`, `duration_ms`, `network_errors`, `console_errors`, `to_json`
- `ignored_network_errors` / `ignored_console_errors` on `Report` — errors suppressed by ignore rules are captured, not silently dropped
- Configurable ignore rules via `ignore:` — `IgnoreRule` supports substring, regex, and wildcard matching on URL/text and failure/type fields
- Default ignore rule suppresses `net::ERR_ABORTED` (analytics beacons, cancelled prefetches)
- Typed exception hierarchy: `PageLoadError` (with partial report), `ConcurrencyLimitError`, `InvocationError`, `ScriptError`, `ParseError`
- Process-wide concurrency limiter (default 5 simultaneous Chromium instances) using Mutex + ConditionVariable — no spinning, slot always released
- SSRF mitigations: scheme allowlist (`http`/`https` only), literal IP blocklist (loopback, link-local, RFC-1918), DNS resolution check
- Full dependency injection throughout — test suite runs in ~0.4 s with no browser, Node, or network required
- GitHub Actions CI workflow (unit suite) and manual Playwright smoke check workflow

[Unreleased]: https://github.com/beflagrant/perchfall/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/beflagrant/perchfall/releases/tag/v0.1.0
