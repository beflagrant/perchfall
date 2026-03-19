# Configuration

## `Perchfall.run` options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `url` | String | — | **Required.** Must be `http` or `https`. |
| `timeout_ms` | Integer | `30_000` | Playwright navigation timeout. Capped at `60_000`. |
| `wait_until` | String | `"load"` | When Playwright considers navigation complete. |
| `scenario_name` | String | `nil` | Optional label included in the report. |
| `cache_profile` | Symbol / Hash | `:query_bust` | Cache behaviour for the request. See below. |

## Cache profiles

Controls how Perchfall handles HTTP caching on each check. Choose a profile based on what you want to measure.

| Profile | URL change | Request headers | Use when |
| --- | --- | --- | --- |
| `:query_bust` | Appends `?_pf=<unix_ts>` | none | **Default.** Forces a cold cache by making every URL unique. |
| `:warm` | none | none | Measuring real-user experience with a primed CDN or browser cache. |
| `:no_cache` | none | `Cache-Control: no-cache` | Bypassing edge caches that honour headers but ignore query strings. |
| `:no_store` | none | `Cache-Control: no-store, no-cache`, `Pragma: no-cache` | Belt-and-suspenders cold cache for CDNs and legacy proxies. |

```ruby
# Warm-cache check — no URL mutation, no headers
Perchfall.run(url: "https://example.com", cache_profile: :warm)

# Cold via Cache-Control (reaches CDN edges that key only on path)
Perchfall.run(url: "https://example.com", cache_profile: :no_cache)

# Custom headers
Perchfall.run(url: "https://example.com", cache_profile: { headers: { "Cache-Control" => "max-age=0" } })
```

**Security note:** Custom profiles are validated against a forbidden-header denylist. `Authorization`, `Cookie`, `Set-Cookie`, `Host`, `X-Forwarded-For`, `X-Forwarded-Host`, and `X-Real-IP` are rejected with `ArgumentError`. See [Security](security.md) for details.

**Note:** Header-based profiles (`setExtraHTTPHeaders`) apply to the initial navigation and all sub-resource requests within the page load, including requests to third-party origins.

## `wait_until` strategies

| Value | When it fires | Use when |
| --- | --- | --- |
| `"load"` | Page `load` event — HTML, images, subresources | **Default. Works for most sites.** |
| `"domcontentloaded"` | DOM parsed; subresources may still be loading | You only care about server-rendered HTML |
| `"networkidle"` | No network activity for 500ms | Avoid for sites with WebSockets or analytics — they never go idle |
| `"commit"` | Navigation response received | Fastest; only confirms a response arrived |

## Concurrency limiting

Perchfall caps simultaneous Chromium processes at **5 by default**, process-wide. Callers beyond the cap block until a slot opens or the timeout expires.

```ruby
# Custom limit at Client construction
client = Perchfall::Client.new(
  limiter: Perchfall::ConcurrencyLimiter.new(limit: 2, timeout_ms: 10_000)
)
report = client.run(url: "https://example.com")
```

When the cap is reached and the timeout expires, `Perchfall::Errors::ConcurrencyLimitError` is raised.

> **Note:** The limit is per-process. For distributed rate limiting across multiple workers, use a Redis semaphore or similar mechanism outside this gem.

## Custom invoker

For testing or to plug in an alternative runner (e.g. a remote Playwright service):

```ruby
client = Perchfall::Client.new(invoker: MyRemotePlaywrightInvoker.new)
report = client.run(url: "https://example.com")
```
