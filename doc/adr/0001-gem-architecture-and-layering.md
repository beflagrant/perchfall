# ADR 0001: Gem Architecture and Class Layering

**Date:** 2026-03-15
**Status:** Accepted

## Context

Perchfall needs to accept a URL, invoke a headless browser, and return a structured report. Several architectural approaches were available:

- A single class with all logic inlined
- A thin Ruby wrapper over a Playwright Ruby gem (e.g. `playwright-ruby-client`)
- A Ruby gem that shells out to a small Node script and parses the result

The gem is intended to be framework-agnostic (usable from Rails, Rake, or plain Ruby) and must be testable without a real browser.

## Decision

The gem is structured in four explicit layers, each with a single responsibility:

```
Client
  └─ PlaywrightInvoker
       ├─ CommandRunner          (process execution)
       └─ PlaywrightJsonParser   (data transformation)
            └─ Report / NetworkError / ConsoleError  (value objects)
```

**`Client`** owns the public API surface. It is intentionally thin — it validates inputs, enforces the concurrency limit, and delegates to the invoker. Its interface is the stable contract callers depend on.

**`PlaywrightInvoker`** owns the command shape and error-promotion logic. It knows what arguments to pass to Node, how to interpret exit codes, and when to raise which error type. It does not know how to run a process or parse JSON.

**`CommandRunner`** wraps `Open3.capture3` behind a one-method interface (`#call(argv_array) → Result`). It is the only class that touches system process APIs.

**`PlaywrightJsonParser`** converts a raw JSON string into domain objects. It is a pure function — no I/O, no side effects.

**Value objects** (`Report`, `NetworkError`, `ConsoleError`) are immutable. `NetworkError` and `ConsoleError` use `Data.define`. `Report` uses a plain class with explicit `freeze` for clarity and Ruby 3.1 compatibility.

The Node script (`playwright/check.js`) is treated as a subprocess with a defined JSON contract, not as a library. The Ruby side never loads Node modules directly.

## Consequences

- Every class can be unit-tested in isolation by injecting fakes at construction time. No test needs a real browser or real process.
- Adding a new invoker (e.g. a remote Playwright service) requires implementing one method: `#run(url:, **opts) → Report`.
- The Node script can be replaced or rewritten without touching Ruby code, as long as the JSON schema is preserved.
- The layering adds indirection. For a project of this size that is a minor cost, justified by the testability and replaceability gains.
