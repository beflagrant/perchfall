# ADR 0015: Report Reflects the Original URL, Not the Effective URL

**Date:** 2026-03-17
**Status:** Accepted

## Context

After ADR 0013 introduced cache busting, `report.url` contained the cache-busted URL (e.g. `https://example.com?_perchfall=1773761362`) rather than the URL the caller passed. This is because `playwright/check.js` reflects `TARGET_URL` — the URL it was given — verbatim into the JSON output, and the parser used that value directly for `Report#url`.

This caused two concrete problems:

1. **Database queries break.** Callers storing reports and querying by URL get mismatches: they query for `https://example.com` but the stored value is `https://example.com?_perchfall=1773761362`.
2. **Leaking implementation details.** `_perchfall` is an internal mechanism. Exposing it in the report's `url` field surfaces implementation noise in logs, dashboards, and serialised payloads that consumers should not need to know about.

## Decision

The original (pre-bust) URL is passed from `Client` to `PlaywrightInvoker` as `original_url:`, and from there to `PlaywrightJsonParser#parse` as `original_url:`. The parser uses `original_url` (when present) in place of `data[:url]` when constructing the `Report`.

`PlaywrightInvoker` defaults `original_url:` to `nil` and falls back to `url` when not provided, so the invoker remains usable directly without a `Client` wrapper and without breaking existing direct callers.

`playwright/check.js` is unchanged. The URL it embeds in JSON is still the effective URL (with the cache-buster), but the Ruby layer discards it in favour of the original URL passed from above.

## Consequences

- `report.url` always reflects the URL the caller passed to `Perchfall.run`, regardless of cache-busting.
- The `_perchfall` parameter is fully internal — it does not appear in any public-facing data.
- The JSON produced by `check.js` still contains the cache-busted URL in its `url` field, but this value is overridden during parsing and never surfaces to callers.
- `PlaywrightInvoker` and `PlaywrightJsonParser` each carry a new `original_url:` parameter. Direct invoker users who care about this distinction should pass it explicitly; those who don't can rely on the fallback.
