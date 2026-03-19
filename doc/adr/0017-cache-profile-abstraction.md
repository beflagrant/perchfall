# ADR 0017 — Cache Profile Abstraction

## Status

Accepted — supersedes [ADR 0013](0013-cache-busting-via-query-parameter.md)

## Context

ADR 0013 introduced `bust_cache: true` as a binary flag that appends a `_perchfall=<timestamp>` query
parameter to force cold-cache page loads. This covered the default case but left two gaps:

1. **Warm-cache testing** — operators may want to measure performance *with* a warm CDN/browser cache
   to understand real-user experience, not just worst-case cold fetches.
2. **Header-based cache control** — CDNs and reverse proxies honour `Cache-Control` / `Pragma` request
   headers. A query-param buster reaches the origin but does not reliably bypass edge caches that key
   solely on the path; header directives are required for that.

`bust_cache: bool` cannot express these distinctions.

Additionally, the query-param name `_perchfall=` was unnecessarily verbose. It has been shortened to
`_pf=` to reduce URL noise in logs and monitoring dashboards.

## Decision

Replace `bust_cache:` with `cache_profile:` (default `:query_bust`) on `Client#run`.

### Built-in profiles

| Profile | URL mutation | Extra request headers |
|---|---|---|
| `:query_bust` | appends `?_pf=<unix_ts>` | none |
| `:warm` | none | none |
| `:no_cache` | none | `Cache-Control: no-cache` |
| `:no_store` | none | `Cache-Control: no-store, no-cache`, `Pragma: no-cache` |

### Custom profile

A Hash is also accepted:

```ruby
client.run(url: "https://example.com", cache_profile: { headers: { "Cache-Control" => "max-age=0" } })
```

The Hash form mutates no URL and sets the given headers verbatim. Any other Hash key is ignored.

### Implementation layers

- **`Client`** resolves the profile symbol/hash into `{ bust_url:, headers: }`, builds the effective
  URL, and forwards `extra_headers:` + `cache_profile:` to `PlaywrightInvoker`.
- **`PlaywrightInvoker`** appends `--headers <json>` to the Node argv when `extra_headers` is
  non-empty; otherwise the flag is omitted entirely.
- **`check.js`** calls `page.setExtraHTTPHeaders(headers)` before `page.goto` when the parsed
  headers object is non-empty. `setExtraHTTPHeaders` applies to the initial navigation and all
  subsequent sub-resource requests within the page load, which is the desired behaviour.
- **`Report`** stores `cache_profile` and includes it in `to_h` / `to_json`, enabling log consumers
  to distinguish warm-cache from cold-cache results without additional context.

## Consequences

**Positive**

- Operators can now run paired warm/cold checks and compare results directly.
- Header-based cache busting reaches CDN edge nodes that ignore query-param variations.
- `cache_profile` in the report enables metric segmentation by cache mode.
- `_pf=` is shorter and less intrusive in URLs.

**Negative / trade-offs**

- `bust_cache:` is a breaking API change. Callers using `bust_cache: false` must migrate to
  `cache_profile: :warm`; `bust_cache: true` maps to `cache_profile: :query_bust`.
- `page.setExtraHTTPHeaders` applies to *all* requests during page load (main document + assets).
  This is intentional for cache-busting purposes but means the headers reach third-party origins
  too. Operators using `:no_cache` / `:no_store` should be aware of this.
- The custom Hash form is validated against a `FORBIDDEN_HEADERS` denylist (see `Client::FORBIDDEN_HEADERS`)
  that rejects credentials and routing headers (`Authorization`, `Cookie`, `Set-Cookie`, `Host`,
  `X-Forwarded-For`, `X-Forwarded-Host`, `X-Real-IP`). Headers outside the denylist are accepted
  verbatim; operators remain responsible for correctness of any headers they inject.
