# ADR 0019: Resource Capture Is Opt-In

**Date:** 2026-03-27
**Status:** Accepted

## Context

To support detection of oversized assets (large images, heavy scripts), Playwright's `response` event can be used to collect metadata for every resource loaded during a page run. This requires attaching a listener to every response and — when the navigation completes — awaiting `response.allHeaders()` in parallel for each collected response in order to read `content-length` and `content-type`.

This is non-trivial overhead: every response object is retained in memory until the navigation settles, and a `Promise.all` over potentially dozens of `allHeaders()` calls is added to the critical path before the result is written to stdout.

## Decision

Resource collection is disabled by default. Callers opt in per-run by passing `capture_resources: true` to `Perchfall.run` / `Client#run`.

When `capture_resources` is false (the default), the JS script attaches no resource listener and performs no `allHeaders()` calls. `report.resources` is always an empty array.

When `capture_resources` is true, the `--capture-resources` flag is passed to the script, the listener is attached, and `report.resources` contains the filtered result.

## Rationale

Perchfall's primary job is detecting page load failures and errors. Resource size profiling is a secondary diagnostic capability — useful on demand, not needed on every check. Paying the collection cost on every run would penalise all callers for a feature most won't use in steady state.

Making it opt-in keeps the zero-argument default fast and the feature available when needed.

## Consequences

- The default run behaviour is unchanged: no extra listener, no `allHeaders()` calls, `report.resources` is `[]`.
- Callers who want resource data must explicitly pass `capture_resources: true`.
- The JS script and Ruby invoker remain clean: `--capture-resources` is absent from the command unless the flag is set, so the script's behaviour is determined entirely by its arguments.
