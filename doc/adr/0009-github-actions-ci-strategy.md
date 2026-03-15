# ADR 0009: GitHub Actions CI Strategy

**Date:** 2026-03-15
**Status:** Accepted

## Context

The gem has two distinct testing concerns with very different resource requirements:

1. **The Ruby unit suite** — 100 examples, no browser, no Node, no network. Runs in ~0.4s. Should give developers fast, automatic feedback on every push and every PR.

2. **Real browser execution** — requires Node 18+, Playwright, and a Chromium binary (~300MB download). Takes 30–60s per check. Cannot be meaningfully parallelised across arbitrary URLs. Its purpose is operational verification ("does this URL actually load?"), not correctness testing of the Ruby code.

Conflating these two concerns into a single CI job would make every PR slow and add a fragile external dependency (network reachability, Chromium availability) to a suite that is otherwise hermetic.

## Decision

Two separate workflows, with distinct triggers:

### `ci.yml` — automatic, on every push and PR

Triggers on `push` to `main` and all `pull_request` events. Installs Ruby 4.0.1 via `ruby/setup-ruby@v1` with `bundler-cache: true`, then runs `bundle exec rspec`. No Node, no Playwright, no network calls.

This is the authoritative green/red signal for code correctness. It is fast enough to not require optimisation (matrix builds, parallelism, etc.) at the current suite size.

### `playwright.yml` — manual only, via `workflow_dispatch`

Triggers exclusively on `workflow_dispatch` — never automatically. Accepts four inputs surfaced in the GitHub Actions UI:

| Input | Type | Default | Notes |
| --- | --- | --- | --- |
| `url` | string | `https://example.com` | Required; validated by `UrlValidator` at runtime |
| `scenario_name` | string | *(blank)* | Optional label in report JSON |
| `wait_until` | choice | `load` | Dropdown constrained to the four Playwright-valid values |
| `timeout_ms` | string | `30000` | Cast to `Integer` by the Ruby script |

The job installs both Ruby and Node 20, runs `npm ci` against the committed `package-lock.json`, installs Chromium with `npx playwright install chromium --with-deps` (includes OS-level dependencies on Ubuntu), then invokes a short inline Ruby script that calls `Perchfall.run` and prints the full JSON report to the Actions log.

Exit codes from the Ruby script map to distinct workflow outcomes:

| Exit code | Meaning |
| --- | --- |
| `0` | `ok: true` — page loaded successfully |
| `1` | `ok: false` — Playwright ran but the page failed (`PageLoadError`) |
| `2` | Gem-level error — Node not found, parse failure, etc. |

## Rationale for key choices

**`workflow_dispatch` only for the smoke workflow.** A scheduled trigger (`on: schedule`) was considered but rejected. A failing scheduled run against a transiently unavailable URL would create noise in the GitHub notifications and no actionable signal — the gem is a library, not a monitoring service. When the consuming Rails app exists, it will run checks on its own schedule and own the alerting. The manual trigger is for ad-hoc verification during development (e.g. confirming the `waitUntil` fix resolved the beflagrant.com timeout).

**Inputs passed via environment variables, not shell interpolation.** The workflow inputs (`${{ inputs.url }}` etc.) are assigned to `env:` keys and read inside the Ruby script via `ENV.fetch`. This prevents shell injection: a URL containing shell metacharacters cannot escape the environment variable boundary. The Ruby gem's own `UrlValidator` provides a second layer of defence at the application level.

**`npm ci` over `npm install`.** `npm ci` requires `package-lock.json` to be present and fails if it is absent or inconsistent with `package.json`. This ensures the Playwright version used in CI is exactly the version tested locally, not whatever npm resolves at run time.

**`bundler-cache: true`.** `ruby/setup-ruby` caches the gem bundle keyed on the `Gemfile.lock`. Since `Gemfile.lock` is intentionally not committed (gem convention), this cache will miss on the first run after any dependency change — acceptable behaviour.

**`--with-deps` on Playwright browser install.** Ubuntu runners on GitHub Actions do not include the shared libraries Chromium requires (`libglib`, `libnss`, etc.). `--with-deps` installs them via `apt-get` as part of the Playwright setup step.

## Consequences

- PRs get a fast, reliable green/red signal with no dependency on external services or browser binaries.
- Real browser smoke checks are available on demand but produce no automatic noise.
- The smoke workflow's exit code convention (0/1/2) is an interface contract between the workflow and any future automation that calls it via `gh workflow run`. Changes to the Ruby script's exit codes must be treated as breaking changes.
- There is currently no artifact upload in the smoke workflow — the JSON report is only visible in the Actions log. If persistent report storage is needed, a future step could upload `report.json` as a workflow artifact or POST it to the Rails app's API.
- The smoke workflow has no concurrency limit at the workflow level. Multiple simultaneous `workflow_dispatch` runs would spawn multiple Chromium instances on separate runners (not the same process), so the gem's `ConcurrencyLimiter` does not apply across runs. This is acceptable for an on-demand tool but worth noting.
