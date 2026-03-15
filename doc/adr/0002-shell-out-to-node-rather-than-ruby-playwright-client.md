# ADR 0002: Shell Out to Node Rather Than Use a Ruby Playwright Client

**Date:** 2026-03-15
**Status:** Accepted

## Context

Playwright has a first-party Ruby client (`playwright-ruby-client`) that wraps the Playwright server protocol. Using it would keep everything in Ruby and avoid a Node runtime dependency.

Alternative: shell out to a small Node script (`playwright/check.js`) using `Open3`, and communicate via stdout JSON.

## Decision

Shell out to Node.

## Rationale

**Playwright's Node SDK is the canonical implementation.** The Ruby client is a community-maintained binding with meaningful lag behind the Node SDK on new browser features, API changes, and bug fixes. For a synthetic monitoring tool, correctness of browser behaviour is the primary concern.

**The Ruby side's job is orchestration, not browser control.** The gem's value is in the structured report, the error hierarchy, and the integration points (concurrency limiting, URL validation). None of that requires Ruby to speak the Playwright protocol directly.

**The subprocess boundary is a clean seam.** `CommandRunner` wraps `Open3.capture3` and returns a `Result` struct. In tests, `FakeCommandRunner` returns canned JSON strings. The entire browser execution path is exercised in tests without spawning a process.

**Exit code semantics encode failure type.** The Node script exits 0 when the JSON output is trustworthy (even for page-level failures like timeouts or DNS errors), and exits 1 only for infrastructure failures where stdout cannot be trusted. This gives `PlaywrightInvoker` a clean binary to interpret: non-zero exit → `ScriptError`; zero exit with `status: "error"` in JSON → `PageLoadError`.

## Consequences

- Node 18+ and Playwright must be installed in any environment that runs the gem for real. This is documented in the README as a requirement.
- The Node script is committed inside the gem at `playwright/check.js` and is included in the gemspec's `files` list.
- Tests that use `FakeCommandRunner` have zero Node dependency and run in ~0.4s for the full suite.
- The JSON contract between Node and Ruby (`playwright/check.js` output schema) is an internal interface. Changes to it require coordinated updates to both `check.js` and `PlaywrightJsonParser`.
