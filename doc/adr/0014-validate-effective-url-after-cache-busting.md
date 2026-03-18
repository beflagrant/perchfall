# ADR 0014: Validate the Effective URL After Cache Busting

**Date:** 2026-03-17
**Status:** Accepted

## Context

ADR 0013 introduced cache busting: `Client#run` appended `?_perchfall=<timestamp>` to the URL before passing it to Playwright (superseded by ADR 0017, which replaced this with the `cache_profile:` abstraction and renamed the param to `_pf=`). In the initial implementation, `UrlValidator#validate!` was called on the *original* URL, before the cache-buster was appended. The modified URL — the one actually sent to Playwright — was never validated.

This is a structural violation of the principle "validate what you send." The gap is narrow in the current implementation (the mutation is purely additive and cannot change the host or scheme), but it creates a structural fragility: any future change to `append_cache_buster` that produces a materially different URL would bypass validation silently. It also means validation and execution operate on different inputs, which is harder to reason about.

## Decision

The effective URL is always built *before* `UrlValidator#validate!` is called, but *after* all other
parameter validation (see ADR 0017 and the R5 correction). `validate!` always receives the effective
URL — the one that will be handed to Playwright.

The ordering in `Client#run` is:

1. Resolve and validate `cache_profile` (ADR 0017)
2. Validate `wait_until` and `timeout_ms`
3. Build `effective_url` (append `?_pf=<ts>` for `:query_bust`; apply no mutation for other profiles)
4. `@validator.validate!(effective_url)`
5. Build and execute the Playwright command with `effective_url`

This ensures the validator and the invoker always see the same URL. Parameter validation is ordered
before URL construction so that a bad `wait_until` or `timeout_ms` does not consume a timestamp
unnecessarily.

## Consequences

- `UrlValidator` validates a URL that may include the `_pf` query parameter (for `:query_bust`). This
  is harmless: the validator checks scheme and host only; query strings are not inspected.
- The invariant "validate what you send" is preserved and structurally enforced by the call order in
  `Client#run`.
- If `append_cache_buster` is ever changed to modify the host or scheme, validation will catch it.
