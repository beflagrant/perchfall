# ADR 0013: Cache Busting via Query Parameter

**Date:** 2026-03-17
**Status:** Accepted

## Context

Synthetic monitoring tools that check the same URL repeatedly are vulnerable to stale responses from CDNs, reverse proxies, and HTTP caches. A cached `200 OK` from a previous run can mask a real outage — the monitoring tool reports success while the origin is down.

The same problem affects Playwright's own internal caching and any intermediate caches that sit between the monitoring host and the origin. A check that always issues the same request may receive a cached response at any layer.

## Decision

`Client#run` accepts a `bust_cache:` keyword argument (default `true`). When enabled, a `_perchfall=<unix_timestamp>` query parameter is appended to the URL before validation and before the URL is passed to Playwright. The integer unix timestamp is used rather than a random value so that the parameter is predictable in logs and easy to filter.

The default is `true` because stale-response masking is a correctness problem for a monitoring tool: the common case for Perchfall is repeated checks against the same URL, and a false-healthy result is worse than a false-unhealthy one. Callers that need a stable URL (e.g. testing a URL that breaks on unknown query parameters) can pass `bust_cache: false`.

The parameter name `_perchfall` was chosen to be both identifiable in server logs and unlikely to conflict with application query parameters.

## Consequences

- The `_perchfall` parameter will appear in server access logs, CDN logs, and analytics pipelines. Callers should be aware of this and filter it where necessary.
- Cache busting is a best-effort mechanism. It defeats query-keyed caches but not caches that ignore query strings. Network-level cache configuration remains the authoritative control.
- `bust_cache: false` is available for any URL where the query parameter causes problems (strict parameter validation, signed URLs, etc.).
