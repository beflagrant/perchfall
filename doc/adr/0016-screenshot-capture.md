# ADR 0016: Screenshot Capture

**Date:** 2026-03-18
**Status:** Accepted

## Context

Synthetic monitoring is most useful when a failure can be diagnosed quickly. A HTTP status code and a list of network or console errors tell you *that* something went wrong, but not always *what the page looked like* at that moment. A screenshot captures visual state — broken layouts, error overlays, blank pages — that no structured field can convey.

Three distinct capture strategies are useful in practice:

- **Always** — capture on every run, regardless of outcome. Useful when building a visual history or comparing page state over time.
- **On error** — capture only when the page load fails. The common case: zero overhead on healthy checks, evidence preserved when it matters.
- **Never** — no capture at all. Appropriate when screenshot data is unwanted (privacy constraints, minimal payloads, environments where disk or bandwidth is constrained).

`on_error` is the right default: it provides diagnostic value without imposing I/O cost on the steady-state happy path.

## Decision

A `screenshots:` option is added to `Perchfall::Client#run`, accepting `:always`, `:on_error`, or `:never` (default `:on_error`). The value is validated in `Client` and forwarded as `--screenshot <value>` to `playwright/check.js`.

`playwright/check.js` captures a PNG via `page.screenshot()` and encodes it as base64, embedding the result in the JSON output under the `screenshot` key (null when not captured). For the `on_error` path, screenshot capture runs inside a `.catch(() => null)` guard so that a screenshot failure never obscures the underlying page error.

`PlaywrightJsonParser` reads `data[:screenshots]` and passes it through to `Report.new`. `Report` exposes a `screenshots` attribute (base64 String or nil). Screenshot data is **excluded from `to_h` and `to_json` by default** — it must be explicitly requested via `report.to_h(include_screenshots: true)` — because a screenshot of an authenticated page can contain session tokens, PII, or internal tooling state that should not leak into logs, error trackers, or message queues through routine serialisation.

Encoding as base64 in the JSON payload keeps the transport self-contained: no temporary files to manage, no cleanup required, no coupling between the Node process's filesystem and the Ruby caller.

## Consequences

- `report.screenshots` is a base64-encoded PNG string when a screenshot was captured, or `nil` otherwise.
- Callers decode with `Base64.decode64(report.screenshots)` if they need raw bytes.
- `report.to_h` and `report.to_json` omit `screenshots` unless `include_screenshots: true` is passed. This is a deliberate safe default — screenshot data has a high surface area for accidental leakage.
- On the `on_error` path, `page.screenshot()` is called inside the rescue block. If the browser context is sufficiently broken to prevent a screenshot (e.g. the page never opened), the capture fails silently and `screenshots` is nil rather than raising.
- The `screenshots:` option is consumed and validated by `Client`; it is not validated again by `PlaywrightInvoker`, which trusts that only valid values arrive via `--screenshot`.
- A full-page PNG at 1x resolution is commonly 200–600 KB; base64 encoding adds ~33% overhead. With `screenshots: :always` and the default concurrency of 5, a single batch can produce 3–4 MB of base64 through stdout. This is acceptable for intermittent diagnostic use but callers running high-frequency or high-concurrency checks should prefer `screenshots: :on_error` (the default) or `screenshots: :never`.

## Future work

The base64-in-JSON transport is the right first cut — self-contained, no filesystem coupling — but it has a natural ceiling. A `screenshot_path:` option that directs the Node script to write the PNG to a caller-specified file and return the path in JSON instead of the encoded data would eliminate the encoding overhead and the stdout pressure entirely. This is the expected next step if screenshot use at `:always` with high concurrency proves to be a bottleneck in practice.
