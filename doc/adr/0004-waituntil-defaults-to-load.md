# ADR 0004: Playwright waitUntil Defaults to "load" Not "networkidle"

**Date:** 2026-03-15
**Status:** Accepted

## Context

Playwright's `page.goto` accepts a `waitUntil` option that controls when the navigation is considered complete:

- `"load"` — fires when the page's `load` event fires (HTML, images, subresources)
- `"domcontentloaded"` — fires earlier, when the DOM is parsed
- `"networkidle"` — waits until there have been no network connections for 500ms
- `"commit"` — fires as soon as the navigation response is received

The initial implementation used `"networkidle"`. This caused `Perchfall.run(url: "https://www.beflagrant.com")` to always time out: the site uses persistent connections (analytics, WebSocket, polling) that never produce 500ms of network silence.

## Decision

Default `waitUntil` to `"load"`.

Expose it as a configurable option (`wait_until:`) threaded through `Client#run` → `PlaywrightInvoker#run` → the Node script's `--wait-until` flag, so callers can override per-check.

```ruby
# Default (load event)
Perchfall.run(url: "https://example.com")

# Faster, less complete
Perchfall.run(url: "https://example.com", wait_until: "domcontentloaded")

# Original behaviour, for sites that need it
Perchfall.run(url: "https://example.com", wait_until: "networkidle")
```

## Rationale

`"load"` correctly represents "the page has finished loading" for the vast majority of sites. `"networkidle"` was a premature optimisation for thoroughness that made the tool unusable on any site with background network activity — which is most modern sites.

The `--wait-until` argument is passed through the argv array (not a shell string), so there is no injection risk from Ruby to Node. The valid values are constrained by Playwright itself; an invalid value causes Playwright to throw an error, which exits 0 with `status: "error"`.

## Consequences

- Sites with SPAs that load content after the `load` event may show incomplete network error capture. Users who need that thoroughness should pass `wait_until: "networkidle"` explicitly.
- `waitUntil` is validated only by Playwright, not by Ruby. A typo in the option (`wait_until: "nettworkidle"`) produces a `PageLoadError` with Playwright's error message rather than an `ArgumentError`. A future improvement could add an allowlist check in `PlaywrightInvoker`.
