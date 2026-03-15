# ADR 0007: Dependency Injection as the Primary Testing Seam

**Date:** 2026-03-15
**Status:** Accepted

## Context

The gem's core operation — spawning a headless browser — is slow, requires external binaries, and has side effects. Tests that spawn real browsers are slow, fragile, and impossible to run in a standard CI environment without Playwright installed. An alternative is to use RSpec's `allow(...).to receive(...)` mocking on internal methods. A third option is constructor-injected collaborators (real objects in production, fakes in tests).

## Decision

All collaborators are injected via keyword arguments at construction time. No class reaches out for its own dependencies. The injection points are:

| Class | Injectable collaborator | Default |
|---|---|---|
| `Client` | `invoker:` | `PlaywrightInvoker.new` |
| `Client` | `validator:` | `UrlValidator.new` |
| `Client` | `limiter:` | `Perchfall.default_limiter` |
| `PlaywrightInvoker` | `runner:` | `CommandRunner.new` |
| `PlaywrightInvoker` | `parser:` | `PlaywrightJsonParser.new` |
| `PlaywrightInvoker` | `script_path:` | `DEFAULT_SCRIPT_PATH` |

Tests inject fakes:

- `FakeCommandRunner` — a real Ruby class (not an RSpec double) that records the last command and returns canned stdout/stderr/exit\_status. Tests for `PlaywrightInvoker` never spawn a process.
- Anonymous invoker classes (inline `Class.new`) in `client_spec` — zero dependency on `PlaywrightInvoker`.
- Isolated `ConcurrencyLimiter` instances in each spec — no shared state with `default_limiter`.

`PlaywrightJsonParser` requires no injection at all; it is a pure function of its string input, tested with fixture JSON strings.

## Rationale over alternatives

**vs. partial mocking (`allow(runner).to receive(:call)`):** Partial mocking couples tests to method names on concrete classes. When the class is refactored, tests break for wrong reasons. `FakeCommandRunner` has no knowledge of RSpec; its interface is defined by what `CommandRunner` actually does.

**vs. integration tests with real Playwright:** Kept to zero in the automated suite. The Node script can be exercised manually (`node playwright/check.js --url https://example.com`). Real-browser tests are an operational concern, not a unit concern.

## Consequences

- The full test suite runs in ~0.4s with no browser, no Node, and no network.
- New collaborators should follow the same pattern: accept an interface, provide a sensible default, document the interface contract in a comment.
- `script_path:` being injectable means the Node script path is a trust boundary. It must never be sourced from user input. This is noted in the security review (S2) but not yet enforced in code.
