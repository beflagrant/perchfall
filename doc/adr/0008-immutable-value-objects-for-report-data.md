# ADR 0008: Immutable Value Objects for Report Data

**Date:** 2026-03-15
**Status:** Accepted

## Context

The gem's output — `Report`, `NetworkError`, `ConsoleError` — is consumed by external systems (Rails apps, background jobs) that may pass the objects between threads, cache them, or serialise them. Mutable report objects would create aliasing hazards: a consumer that holds a reference could observe mutations made by another consumer or by internal gem code.

Additionally, `CommandRunner` produces a `Result` that crosses the boundary between the runner and the invoker.

## Decision

All data-carrier objects are immutable.

**`NetworkError`, `ConsoleError`, and `IgnoreRule`** use `Data.define` (Ruby 3.2+). `Data` instances are frozen by definition and have value equality built in. `IgnoreRule` value equality matters in practice — a caller that accidentally supplies a duplicate rule will produce a deduplicate-able list.

**`Report`** uses a plain class with explicit `freeze` in `initialize`. `Data.define` was considered but rejected for `Report` because `Report` has a non-trivial number of attributes, optional keyword arguments with defaults, and computed methods (`ok?`, `to_h`, `to_json`, `==`). A plain class makes all of this more readable and explicit than a `Data.define` block.

**`CommandRunner::Result`** uses `Data.define`. It is an internal type that crosses one boundary and has no behaviour beyond its fields.

**`Report#==`** is implemented via `to_h` comparison. This means two reports are equal if their serialised form is equal, which is the correct notion of equality for a value object representing a monitoring result.

## Consequences

- Frozen objects cannot be mutated after construction. Callers that attempt to modify a report (e.g. `report.network_errors << new_error`) receive a `FrozenError`. This is intentional. The same applies to the `ignored_network_errors` and `ignored_console_errors` arrays added in ADR 0010/0011.
- `Data.define` is Ruby 3.2+. The gemspec specifies `required_ruby_version >= 3.2.0`.
- `NetworkError` defines a `method` attribute, which shadows `Object#method`. This is a known issue (R4 from the code review) that has not yet been fixed. The workaround is to avoid calling `.method(:something)` on a `NetworkError` instance. Renaming to `http_method` is the correct fix.
- `Report#==` uses `timestamp.iso8601` (one-second resolution) for comparison. Two reports from the same run created within the same second would be considered equal even if other attributes differed — though in practice this cannot happen since a `Report` is constructed once. This is a known minor imprecision (R3 from the code review).
