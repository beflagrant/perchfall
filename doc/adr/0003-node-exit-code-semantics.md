# ADR 0003: Node Script Exit Code Semantics

**Date:** 2026-03-15
**Status:** Accepted

## Context

The Node script can fail in two distinct ways:

1. **Infrastructure failure** — Node cannot launch, the script crashes before writing anything to stdout, or Playwright's browser binary is missing. Stdout is empty or garbage.
2. **Page-level failure** — Playwright ran, navigated (or attempted to), and produced a structured result, but the page itself failed: DNS error, timeout, HTTP 5xx, etc. Stdout contains valid JSON.

The Ruby side (`PlaywrightInvoker`) must distinguish these two cases to raise the right exception.

## Decision

- **Exit 1** is reserved exclusively for infrastructure failures where stdout cannot be trusted.
- **Exit 0** is used for all outcomes where the JSON output is trustworthy, including page-level failures. In this case `status: "error"` in the JSON payload signals the failure, and `error` contains the Playwright error message.

```
exit 0 + status:"ok"    → Report (ok? == true)
exit 0 + status:"error" → PlaywrightInvoker raises PageLoadError (carries Report)
exit 1                  → PlaywrightInvoker raises ScriptError
```

The Node script wraps the entire browser session in a `try/catch`. Page-level errors (Playwright's `TimeoutError`, `net::ERR_NAME_NOT_RESOLVED`, etc.) are caught and serialised into the JSON before exiting 0. Only unhandled exceptions in the outer `run().catch(...)` wrapper exit 1.

## Consequences

- `PlaywrightInvoker#parse` can make a simple binary decision: non-zero exit status raises `ScriptError` immediately; zero exit means the stdout is JSON and should be parsed.
- `network_errors` and `console_errors` arrays are always present in the JSON (never null), even on `status: "error"`, because Playwright may have captured some before the failure occurred.
- If a future version of the Node script needs additional exit codes (e.g. for distinguishing timeout from DNS failure at the process level), this ADR should be revisited.
