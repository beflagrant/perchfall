# Configuration

## `Perchfall.run` options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `url` | String | — | **Required.** Must be `http` or `https`. |
| `timeout_ms` | Integer | `30_000` | Playwright navigation timeout. Capped at `60_000`. |
| `wait_until` | String | `"load"` | When Playwright considers navigation complete. |
| `scenario_name` | String | `nil` | Optional label included in the report. |
| `cache_profile` | Symbol / Hash | `:query_bust` | Cache behaviour for the request. See below. |
| `retries` | Integer | `0` | Additional attempts on a retryable failure (`N` retries = `N+1` attempts). Capped at `10`. See [Retries](#retries). |
| `retry_on` | Array&lt;Symbol&gt; / Proc | `[:load_error, :script_error, :server_error]` | Which failure conditions are retryable. Only consulted when `retries > 0`. |
| `retry_backoff_ms` | Integer | `250` | Exponential backoff between attempts (`250`, `500`, `1000`…). `0` disables. Capped at `30_000`. |

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

## Retries

Retries are **opt-in**. With the default `retries: 0`, every run is a single
attempt and `retry_on` / `retry_backoff_ms` are inert — behaviour is unchanged.

Set `retries:` to re-run on a *retryable* failure. You decide what counts as
retryable via `retry_on:` — load failures, process failures, and 5xx are
retried by default; assertion (JavaScript console) errors never are.

```ruby
# Smooth over small timing blips: up to 2 extra attempts on the defaults
Perchfall.run(url: "https://example.com", retries: 2)

# Only retry server-side 5xx, with a snappier backoff
Perchfall.run(
  url:              "https://example.com",
  retries:          3,
  retry_on:         [:server_error],
  retry_backoff_ms: 100
)
```

### Retryable conditions

`retry_on:` accepts an array of these named symbols:

| Condition | Matches | Default on? |
| --- | --- | --- |
| `:load_error` | Page failed to load — `status: "error"` (nav timeout, connection reset, DNS) | ✅ |
| `:script_error` | The Node/Playwright process failed (`Errors::ScriptError`) | ✅ |
| `:server_error` | A response returned HTTP 5xx | ✅ |
| `:client_error` | A response returned HTTP 4xx | — |
| `:network_error` | A sub-resource failed with a `net::ERR_*` error | — |

JavaScript/console (assertion) errors are **never** retryable — they are real
defects, not timing blips, so they cannot be named here.

**A failure is retried only when *every* reason it failed is a declared
condition.** A 5xx that also carries a console error is *not* retried when only
`:server_error` is declared — the assertion failure would never clear, so the
run would just fail again after exhausting the backoff budget.

For a policy the named set can't express, pass a predicate proc. It receives the
outcome — a `Report` or the raised exception — and returns truthy to retry:

```ruby
Perchfall.run(url: "https://example.com", retries: 2, retry_on: ->(outcome) {
  outcome.is_a?(Perchfall::Report) && outcome.http_status == 503
})
```

### Backoff

`retry_backoff_ms:` (default `250`) is the base for an exponential delay between
attempts: `250ms`, then `500ms`, then `1000ms`, and so on. Pass `0` for no
delay. The browser concurrency slot is released while waiting, so a retrying run
never starves other checks. Each `:query_bust` retry also gets a fresh `_pf=`
timestamp for a genuinely cold re-fetch.

> **Not retried:** `ConcurrencyLimitError` (back-pressure — back off and retry
> at the caller level), `InvocationError` (Node missing — a config problem),
> `ParseError`, and `ArgumentError` are never auto-retried.

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
