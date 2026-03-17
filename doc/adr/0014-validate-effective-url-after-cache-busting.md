# ADR 0014: Validate the Effective URL After Cache Busting

**Date:** 2026-03-17
**Status:** Accepted

## Context

ADR 0013 introduced cache busting: `Client#run` appends `?_perchfall=<timestamp>` to the URL before passing it to Playwright. In the initial implementation, `UrlValidator#validate!` was called on the *original* URL, before the cache-buster was appended. The modified URL — the one actually sent to Playwright — was never validated.

This is a structural violation of the principle "validate what you send." The gap is narrow in the current implementation (the mutation is purely additive and cannot change the host or scheme), but it creates a structural fragility: any future change to `append_cache_buster` that produces a materially different URL would bypass validation silently. It also means validation and execution operate on different inputs, which is harder to reason about.

## Decision

Cache busting is applied *before* `UrlValidator#validate!` is called. `validate!` always receives the effective URL — the one that will be handed to Playwright.

The ordering in `Client#run` is:

1. `append_cache_buster(url)` → `effective_url`
2. `@validator.validate!(effective_url)`
3. Build and execute the Playwright command with `effective_url`

This ensures the validator and the invoker always see the same URL.

## Consequences

- `UrlValidator` validates a URL that includes the `_perchfall` query parameter. This is harmless: the validator checks scheme and host only; query strings are not inspected.
- The invariant "validate what you send" is restored and is now structurally enforced by the call order in `Client#run`.
- If `append_cache_buster` is ever changed to modify the host or scheme, validation will catch it correctly.
