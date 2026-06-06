# ADR 0021: Opt-In Retry for Caller-Declared Transient Conditions

**Date:** 2026-06-05
**Status:** Accepted

## Context

A synthetic browser check can fail for reasons that have nothing to do with the
page being broken: a navigation that timed out by a hair, a connection reset
mid-flight, a server returning a 5xx while it restarts. These are transient — a
second attempt moments later would have passed. With a single-shot run, such a
blip becomes a failed report (`report.ok? == false`) or a raised `ScriptError`,
producing false alarms.

Not every failure is transient, though. A 404 on an asset, a JavaScript console
error, or a DNS misconfiguration is a real defect: retrying only wastes time and
still fails. Whether a given failure is "worth retrying" is also a matter of
intent that varies by caller and target — what is a flaky blip for one service
is a hard SLA breach for another.

## Decision

Retries are **opt-in** and the **caller declares which conditions are
retryable**.

- `retries:` (default `0`) sets the number of *additional* attempts. `0`
  preserves the existing single-shot behaviour exactly.
- `retry_on:` declares retryable conditions, in one of two forms:
  - An array of named symbols drawn from `RetryPolicy::CONDITIONS`
    (`:load_error`, `:script_error`, `:server_error`, `:client_error`,
    `:network_error`). Default: `[:load_error, :script_error, :server_error]`.
  - A predicate proc receiving the outcome (a `Report` or the raised exception)
    and returning truthy to retry — an escape hatch for callers whose policy
    the named set cannot express.
- `retry_backoff_ms:` (default `250`) controls an exponential delay between
  attempts (250 / 500 / 1000…); `0` disables it.

For the symbol form, a run is retried only when **every** reason it is not-ok is
a declared condition. Console/JavaScript (assertion) errors are deliberately
absent from `CONDITIONS` and can never be opted into via symbols.

The retry loop lives in `Client`, which already owns validation and the
concurrency slot. Classification is delegated to `Perchfall::RetryPolicy`, a
pure module. The backoff sleep happens outside `ConcurrencyLimiter#acquire`, so
a waiting run does not hold a browser slot while sleeping. Each `:query_bust`
retry uses a fresh cache-busting timestamp.

## Rationale

Hardcoding our own notion of "transient" would bake a policy decision into the
library that legitimately differs per caller. Exposing the conditions and
letting the caller declare them keeps Perchfall honest: it reports what it saw,
and the caller decides what a retry can fix.

The "every reason must be opted in" rule prevents the worst failure mode of
naive retry — repeatedly re-running a check that is doomed by a real defect (an
assertion failure alongside a transient 5xx) and reporting failure anyway after
burning the full backoff budget.

Releasing the concurrency slot during backoff keeps a multi-attempt run from
starving other checks while it waits.

## Consequences

- Default behaviour is unchanged: `retries: 0` means one attempt, as before.
- `run!` benefits automatically — it raises `PageLoadError` only after retries
  are exhausted and the final report is still not ok.
- `ConcurrencyLimitError`, `InvocationError`, `ParseError`, and `ArgumentError`
  are never auto-retried; only `ScriptError` (via `:script_error`) and not-ok
  reports are eligible.
- Classification logic is centralised in `RetryPolicy` and testable with plain
  `Report` objects and exceptions — no browser or process needed.
- A future enhancement could record the attempt count on the `Report`; it is
  deliberately omitted here to keep the value object and its schema unchanged.
