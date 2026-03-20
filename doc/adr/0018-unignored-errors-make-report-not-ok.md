# ADR 0018: Unignored Network and Console Errors Make a Report Not OK

**Date:** 2026-03-19
**Status:** Accepted

## Context

`Report#ok?` previously returned `true` whenever the Node script reported `status: "ok"` — meaning the page reached the `waitUntil` milestone without a fatal load error. Network errors (broken assets, failed API calls) and console errors were captured and exposed on the report, but did not affect `ok?`. A caller had to inspect those arrays explicitly to detect them.

This created a silent failure mode: a monitoring check could return `ok? => true` while the page had broken sub-resources or JavaScript exceptions. The ignore-rule system (ADR 0010, ADR 0011) already provides the mechanism for callers to acknowledge known false positives — but it had no enforcement teeth.

## Decision

`Report#ok?` returns `true` only when all three conditions hold:

1. `status == "ok"` (the page reached the load milestone)
2. `network_errors.empty?` (no unignored network failures)
3. `console_errors.empty?` (no unignored console errors)

Any unignored error in either array causes `ok?` to return `false`, which causes `PlaywrightInvoker#raise_if_page_load_error` to raise `Perchfall::Errors::PageLoadError`. The `PageLoadError` carries the full report, so callers can inspect which errors triggered the failure.

Errors moved to `ignored_network_errors` or `ignored_console_errors` by an `IgnoreRule` do not affect `ok?` — they have been explicitly acknowledged by the caller.

## Rationale

The purpose of a synthetic check is to detect real problems. A monitoring system that silently passes a page with broken assets or JavaScript exceptions provides false confidence. The correct unit of "this check passed" is: the page loaded *and* nothing unexpected went wrong.

The ignore-rule system exists precisely so callers can draw that line deliberately. An error that appears in `network_errors` is one the caller has not yet addressed — either by fixing it or by deciding it is acceptable and adding an `IgnoreRule`. Treating it as a non-failure would remove the incentive to address it at all.

## Consequences

- Existing checks that were passing with known, un-ignored errors will now raise `PageLoadError`. Callers must either fix the errors or add `IgnoreRule` entries to acknowledge them.
- The `PageLoadError` carries the partial `Report`, so callers can log or inspect which errors caused the failure before deciding how to respond.
- `Report#ok?` and the ignore-rule system now form a closed loop: every error is either fixed, ignored by rule, or surfaces as a failure.
- The `bin/console` fake-report example in `perchfall-notify` remains valid — it constructs a report with empty error arrays, so `ok?` returns `true` as expected.
