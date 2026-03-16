# ADR 0012: DNS Resolution Check as SSRF Defence-in-Depth

**Date:** 2026-03-15
**Status:** Accepted

## Context

ADR 0005 introduced a hostname blocklist that rejects literal private IP addresses (loopback, link-local, RFC-1918) and `localhost`. It explicitly documented one unmitigated vector:

> DNS-based SSRF (a public hostname that resolves to a private IP) is **not** mitigated here. … The correct defence for this attack vector is network-level egress filtering.

A security review (finding S1) confirmed this as a High-risk gap. An attacker who controls a hostname's DNS record can register `attacker.com`, point it at a public IP to pass validation, then flip the record to `169.254.169.254` before Playwright's own DNS lookup resolves — causing Chromium to fetch the AWS instance metadata endpoint (or any other internal address).

The TOCTOU race is real and cannot be eliminated in-process: Playwright performs its own DNS lookup independently, and there is no way to force it to reuse ours. However, resolving the hostname at validation time meaningfully shrinks the attack window. An attacker now needs the DNS TTL to expire and the flip to occur within milliseconds (between our lookup and Playwright's), rather than having an arbitrarily wide window.

## Decision

`UrlValidator` gains a third check: **DNS resolution blocking**.

After the scheme allowlist and the literal-address blocklist pass, `UrlValidator` resolves the hostname via `resolver.getaddresses(hostname)` and checks every returned address against the existing `BLOCKED_RANGES`. If any address falls in a blocked range, `ArgumentError` is raised before the command is built.

Literal IP addresses (already handled by the blocklist in Rule 2) are skipped — `parse_ip` returning non-nil is used as the skip condition, so a literal `192.168.1.1` is still caught by the existing path without an unnecessary DNS call.

The resolver is injectable via `UrlValidator.new(resolver:)`, defaulting to `Resolv` (Ruby stdlib). The injected object must respond to `#getaddresses(hostname) → Array<String>`. This keeps the validator unit-testable without real DNS calls and allows callers to substitute an alternative resolver (e.g. one with a shorter timeout, or one backed by a trusted DNS-over-HTTPS service).

Non-resolving hostnames (empty array from `getaddresses`) are allowed through. The DNS failure case — a genuinely non-existent domain — is already handled naturally: Playwright will fail to navigate and return a `PageLoadError`.

## Explicit Remaining Limitation

This check does **not** eliminate the SSRF risk. It is defence-in-depth only. The authoritative control remains network-level egress filtering (security groups, firewall rules, or an outbound proxy with ACLs) on the host running Chromium. Deployments accepting untrusted URLs must enforce this externally.

## Consequences

- The validation path now makes a synchronous DNS call for any non-literal-IP hostname. This adds latency to `validate!` — typically single-digit milliseconds on a warm resolver, but potentially hundreds of milliseconds on a cold or slow resolver. This is acceptable because `validate!` is called before spawning Chromium (which takes far longer).
- `UrlValidator` now requires `resolv` (Ruby stdlib, always available).
- The `resolver:` injection point follows the same DI pattern established in ADR 0007 for all other collaborators.
- Callers that legitimately monitor internal services and currently pass a custom `validator:` are unaffected; they were already responsible for their own validation logic.
- ADR 0005's "Explicit Non-Decision" is superseded: DNS-based SSRF is now partially mitigated. The limitation comment in `UrlValidator`'s source is updated to reflect that a TOCTOU race remains but the window is significantly narrowed.
