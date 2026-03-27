# ADR 0020: Resource Threshold Filtering Happens in Ruby, Not in JS

**Date:** 2026-03-27
**Status:** Accepted

## Context

When resource capture is enabled (ADR 0019), only resources above a configured size threshold are useful to report — returning every resource on a typical page (often 50–100+ entries) would be noisy and wasteful.

The threshold could be applied in one of two places:

1. **In the JS script** — pass the threshold as a CLI argument; the script only emits resources that exceed it.
2. **In Ruby** — the script emits all resources; the parser filters before constructing the `Report`.

A related question: how should resources with an absent `content-length` (chunked encoding, inline data) be handled, since their size is genuinely unknown?

## Decision

The JS script emits all resources without filtering. Threshold filtering is applied in `PlaywrightJsonParser#parse_resources` in Ruby, after JSON is received and before the `Report` is constructed.

The default threshold is 200 KB (`200_000` bytes), configurable per-run via `large_resource_threshold_bytes:`.

Resources with `transfer_size: nil` (absent `content-length`) are always included in `report.resources`, regardless of threshold. They cannot be proven to be below the threshold.

## Rationale

**JS stays dumb.** The script's job is to collect raw data faithfully and return it. Policy — what counts as "large", what a caller cares about — belongs in the Ruby layer where it can be expressed, tested, and changed without touching Node.

**Threshold is a Ruby-side concern.** The threshold is configured at `run` time in Ruby and never needs to cross the process boundary. Passing it to JS would require additional argument parsing, validation, and testing in the script for no benefit — the filtering happens after the script exits anyway.

**Unknown sizes are conservatively included.** A resource whose `content-length` is absent could be arbitrarily large. Silently dropping it would be a false negative — the resource might be the very large asset the caller is trying to find. Including it makes the miss impossible and leaves the caller to decide what to do with a `nil` transfer size.

## Consequences

- When `capture_resources: true`, the script sends the full resource list over stdout. On pages with many resources this is more data than if JS filtered first, but the overhead is bounded and the simplicity trade-off is worth it.
- `report.resources` contains only resources at or above the threshold, plus any with unknown size.
- `transfer_size: nil` is documented as "unknown, not zero" — callers must not treat it as 0 bytes.
- `ok?` is not affected by `resources` — size is a metric, not a pass/fail signal.
