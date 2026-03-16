# ADR 0011: Unified Ignore Rule System

**Date:** 2026-03-15
**Status:** Accepted

## Context

ADR 0010 introduced configurable ignore rules for network errors (`ignore:`) and a separate mechanism for console errors (`ignore_console:`), backed by two distinct filter classes (`NetworkErrorFilter`, `ConsoleErrorFilter`) and two default constants (`DEFAULT_IGNORE_RULES`, `DEFAULT_IGNORE_CONSOLE_RULES`).

This design had a structural asymmetry: network rules were first-class (non-empty defaults, short option name) while console rules felt like an afterthought (empty defaults, longer option name, separate class). Any caller suppressing both a third-party 403 and a noisy console warning had to manage two separate lists and two separate option keywords.

Additionally, `IgnoreRule#match?` originally accepted a domain object (`NetworkError`) directly, coupling the rule's matching logic to a specific error type. This prevented reuse across error types without duplicating the rule definition.

## Decision

Consolidate the ignore rule system into three components:

### `IgnoreRule` — gains `target:` field

`IgnoreRule` is extended with a `target:` field that declares which error type the rule applies to:

| Value | Applies to |
| --- | --- |
| `:network` | `NetworkError` only (matched on `url` + `failure`) |
| `:console` | `ConsoleError` only (matched on `text` + `type`) |
| `:all` | Both error types |

`match?` is changed to accept two plain strings (`primary`, `secondary`) rather than a domain object. The filter is responsible for extracting the correct fields from each error before calling `match?`. This keeps `IgnoreRule` generic — it knows nothing about `NetworkError` or `ConsoleError`.

### `ErrorFilter` — replaces `NetworkErrorFilter` and `ConsoleErrorFilter`

A single `ErrorFilter` class accepts a unified rule list and exposes two methods:

- `filter_network(errors)` — applies `:network` and `:all` rules to `NetworkError` arrays
- `filter_console(errors)` — applies `:console` and `:all` rules to `ConsoleError` arrays

Both methods return `{ kept: [...], ignored: [...] }`. The rule partitioning by `target` happens once at construction time, not on every filter call.

`NetworkErrorFilter` and `ConsoleErrorFilter` are deleted.

### Single `ignore:` option and `DEFAULT_IGNORE_RULES`

`Perchfall.run`, `Client#run`, and `PlaywrightInvoker#run` accept a single `ignore:` keyword argument containing a mixed list of `IgnoreRule`s with any `target:` value. `DEFAULT_IGNORE_CONSOLE_RULES` is removed. `DEFAULT_IGNORE_RULES` now covers all error types:

```ruby
Perchfall::DEFAULT_IGNORE_RULES = [
  IgnoreRule.new(pattern: //, type: "net::ERR_ABORTED", target: :network),
].freeze
```

Callers extend this single list:

```ruby
Perchfall.run(
  url: "https://thepeachtruck.com",
  ignore: [
    IgnoreRule.new(pattern: "shop.app/pay",   type: "HTTP 403", target: :network),
    IgnoreRule.new(pattern: "ReferenceError", type: "error",    target: :console),
    IgnoreRule.new(pattern: "GTM",            type: "*",        target: :all),
  ]
)
```

## Rationale for key choices

**`target:` on the rule rather than separate rule classes.** A `NetworkIgnoreRule` / `ConsoleIgnoreRule` split would restore the original asymmetry at the class level. A single `IgnoreRule` with a `target:` field expresses intent in one place, allows `:all` as a first-class concept, and means a caller's ignore list is a flat array of uniform objects.

**`match?` takes plain strings, not domain objects.** The alternative — overloading `match?` to accept either error type — would require `IgnoreRule` to know about both domain classes. Plain strings keep the rule a pure value object. The field extraction (`e.url`, `e.text`, etc.) belongs in `ErrorFilter`, which does know about the domain types.

**One `ErrorFilter`, two methods.** Separate filter classes per error type would require callers (and `PlaywrightJsonParser`) to manage two filter instances. A single filter instance constructed from one rule list and called with two different methods matches how the rules are authored — as a single list — and how they are consumed — in one parser pass.

**`DEFAULT_IGNORE_CONSOLE_RULES` removed rather than merged.** The constant was empty and existed only to mirror `DEFAULT_IGNORE_RULES`. Keeping an empty constant as a extension point is speculative API design. If a future universally-ignorable console error category is identified, it can be added to `DEFAULT_IGNORE_RULES` with `target: :console`.

## Consequences

- The public API surface shrinks: one `ignore:` option replaces `ignore:` + `ignore_console:`. Callers who adopted `ignore_console:` in the brief window between ADR 0010 and this ADR must migrate to `ignore:` with `target: :console` rules.
- `IgnoreRule` now requires `target:`. Existing `IgnoreRule.new(pattern:, type:)` calls without `target:` will raise `ArgumentError` at construction time — a clear, immediate failure rather than silent misbehaviour.
- `NetworkErrorFilter` and `ConsoleErrorFilter` are deleted. Code that references them directly must be updated to use `ErrorFilter`.
- `Report#ignored_console_errors` and `Report#ignored_network_errors` are unchanged — the split at the report level remains, giving consumers a complete audit trail of what was suppressed and why.
- The `:all` target enables rules that apply across both error types from a single `IgnoreRule` definition — useful for third-party integrations like tag managers that produce both network and console noise.
