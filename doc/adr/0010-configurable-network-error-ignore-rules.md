# ADR 0010: Configurable Network Error Ignore Rules

**Date:** 2026-03-15
**Status:** Accepted

## Context

Playwright captures every failed sub-resource request during a page load. In practice, two categories of failure appear consistently but are not signals of a problem with the target page:

1. **Browser-aborted requests (`net::ERR_ABORTED`)** — the browser intentionally cancels third-party beacon calls (analytics, tracking pixels) during headless runs. These are never a real failure.

2. **Third-party 4xx responses** — services embedded in a page (e.g. Shop Pay's payment widget, social login iframes) may return 4xx status codes to requests made by a headless Chromium that lacks the session cookies or referrer context those services require. The target page loads correctly; the 403 is an artifact of the headless context.

The previous implementation hard-coded a single filter that dropped all `net::ERR_ABORTED` entries in `PlaywrightJsonParser`. This had two problems:

- It was invisible to consumers — filtered errors simply disappeared with no audit trail.
- It covered only one failure category. Third-party 4xx responses required a separate solution.

Simply dropping all 4xx sub-resource errors is too broad — a real missing asset (404 on `app.js`) is a meaningful signal.

## Decision

Introduce a configurable ignore-rule system with three new classes and one extension to `Report`.

### `IgnoreRule` (`lib/perchfall/ignore_rule.rb`)

A `Data.define` value object with two fields:

| Field | Accepted types | Semantics |
| --- | --- | --- |
| `url_pattern` | `String` or `Regexp` | String: substring match. Regexp: full match via `match?`. |
| `failure` | `String`, `Regexp`, or `"*"` | String: substring match. Regexp: full match. `"*"`: matches any failure. |

A rule matches a `NetworkError` when both `url_pattern` and `failure` match. Requiring both fields prevents over-broad rules: a rule suppressing 403s from `shop.app` will not suppress 403s from other domains, and will not suppress other failure types from `shop.app`.

### `NetworkErrorFilter` (`lib/perchfall/network_error_filter.rb`)

Accepts a list of `IgnoreRule` objects. Given an array of `NetworkError`s, returns `{ kept: [...], ignored: [...] }`. An error is ignored if *any* rule matches it.

Returning both arrays rather than only the kept list ensures no information is lost — consumers can audit what was suppressed.

### `Report#ignored_network_errors`

A new attribute alongside the existing `network_errors`. Both are always arrays. `to_h` and `to_json` include `ignored_network_errors` so the full picture is available in serialised form.

### `Perchfall::DEFAULT_IGNORE_RULES`

A module-level constant that replaces the previous hard-coded `ERR_ABORTED` filter:

```ruby
Perchfall::DEFAULT_IGNORE_RULES = [
  IgnoreRule.new(url_pattern: //, failure: "net::ERR_ABORTED"),
].freeze
```

`url_pattern: //` matches every URL, so this rule suppresses `ERR_ABORTED` regardless of origin — the previous behaviour, now expressed as a first-class rule.

### Caller API

`Perchfall.run` and `Client#run` accept an `ignore:` keyword argument:

```ruby
Perchfall.run(
  url: "https://thepeachtruck.com",
  ignore: [
    Perchfall::IgnoreRule.new(url_pattern: "shop.app/pay", failure: "HTTP 403"),
  ]
)
```

`Client#run` merges caller-supplied rules with `DEFAULT_IGNORE_RULES` before forwarding. Callers extend the defaults; they do not replace them. If a caller genuinely needs to disable the default `ERR_ABORTED` filter they must construct a `Client` directly and supply their own `ignore:` list — this is an intentional friction point.

The merged list flows through `PlaywrightInvoker#run` → `NetworkErrorFilter` → `PlaywrightJsonParser`, where it splits the raw error array into `kept` and `ignored` before constructing the `Report`.

## Rationale for key choices

**`IgnoreRule` as `Data.define`.** The rule is a pure value with no behaviour beyond matching. `Data.define` gives value equality for free, which matters for testing and for deduplication if a caller accidentally supplies a duplicate rule.

**Both `String` and `Regexp` for patterns.** String substring matching covers the common case (`"shop.app/pay"`) without requiring callers to write regexes. Regexp covers cases where substring is ambiguous (e.g. matching `google-analytics.com` without also matching `not-google-analytics.com`).

**`"*"` wildcard for failure.** A common need is "ignore all failures from this domain, whatever they are" — e.g. a known-flaky third-party widget. The `"*"` literal is more readable than `/./` and avoids confusion with Regexp semantics.

**Filter at parse time, not at report-read time.** Filtering in `PlaywrightJsonParser` keeps `Report` a pure value — it holds the result of a decision already made, rather than re-evaluating rules on every access. This is consistent with the rest of the architecture.

**Merge, not replace.** Callers extend the default ignore list rather than replacing it. This prevents `ERR_ABORTED` noise from reappearing when a caller passes any `ignore:` rules. A caller who genuinely wants no defaults can construct `Client` directly.

**`ignored_network_errors` in the report.** Dropping matched errors silently makes debugging difficult — a consumer cannot tell whether an error was absent or suppressed. Including the suppressed list in the report (and in `to_json`) means the consuming application can log or inspect what was ignored without needing to re-run the check.

## Consequences

- Consumers can suppress known third-party noise on a per-call basis without modifying gem internals.
- `Report#to_h` and `to_json` now include `ignored_network_errors`. Consumers that assert on the exact key set of the serialised report (e.g. JSON schema validation) will need to add this field.
- The default `ERR_ABORTED` suppression is now visible and documented as `DEFAULT_IGNORE_RULES` rather than being a hidden implementation detail of the parser.
- `PlaywrightInvoker` no longer holds a single reusable parser instance; it constructs a fresh `PlaywrightJsonParser` on each `#run` call with the per-call filter. This is cheap (no I/O, no shared state) and simplifies the threading model.
- `IgnoreRule` matching is substring-based for strings, which means an overly broad `url_pattern` (e.g. `"."`) would match many URLs. This is a caller concern; the gem does not validate rule specificity.
- DNS-based SSRF (a public hostname resolving to a private IP) remains out of scope, as documented in ADR 0005.
