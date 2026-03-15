# ADR 0006: Process-Wide Concurrency Limiting via Semaphore

**Date:** 2026-03-15
**Status:** Accepted

## Context

A security review identified that unbounded calls to `Perchfall.run` — e.g. from a Sidekiq worker processing user-submitted URLs — would spawn an unbounded number of headless Chromium instances. Each instance consumes ~100MB of RAM and significant CPU. This is a resource exhaustion vector (A2), and also a practical operational concern for any production deployment.

No concurrency control existed in the initial implementation.

## Decision

`ConcurrencyLimiter` is a `Mutex` + `ConditionVariable` semaphore:

- Callers that find all slots occupied **block** (up to `timeout_ms`) rather than failing immediately or spawning freely.
- When `timeout_ms` elapses without a slot opening, `Errors::ConcurrencyLimitError` is raised.
- The slot is released in an `ensure` block, so an exception inside the browser run cannot leak a slot.

A single process-wide instance is provided via `Perchfall.default_limiter` (lazy method, not a constant — see below), defaulting to **5 concurrent browser instances**.

`Client` accepts `limiter:` for injection, enabling tests to use isolated per-example limiters rather than the shared default.

## Key Implementation Notes

**Lazy initialisation.** `default_limiter` is a module method with `@default_limiter ||=`, not a constant. A constant defined at load time (`DEFAULT_LIMITER = ConcurrencyLimiter.new(...)`) would instantiate the `Mutex` when the gem is required. This caused every spec to wait 30 seconds at exit: the `condvar.wait` inside a test thread was blocked on the shared mutex, and Ruby's main thread waits for all non-daemon threads before exiting. Making the limiter lazy means requiring the gem in tests that never call `Client.new` without a `limiter:` argument does not create any threads or mutexes.

**`timeout_ms: 0` means "fail immediately if no slot."** This emerged from TDD: a spec titled "raises ConcurrencyLimitError without waiting when limit is 0" initially used `described_class.new(limit: 0)` without specifying `timeout_ms`. The condvar then waited the full 30-second default before raising. The correct formulation is `described_class.new(limit: 0, timeout_ms: 0)`: `timeout_ms: 0` sets `deadline = now`, so `remaining <= 0` on the first iteration and the error is raised without entering `condvar.wait`.

## Consequences

- The default limit of 5 is a starting point. Production deployments should tune this based on available memory and the concurrency of their job queue. It is configurable at the point of `Client` construction.
- Callers that block waiting for a slot are blocked on a Ruby mutex — they hold their thread. In a Sidekiq context this is one Sidekiq thread per blocked check. Setting `timeout_ms` appropriately (and equal to or less than the job's own timeout) prevents thread exhaustion.
- The limiter is per-process, not per-host. Distributed rate limiting across multiple workers requires a different mechanism (Redis semaphore, etc.) outside the scope of this gem.
