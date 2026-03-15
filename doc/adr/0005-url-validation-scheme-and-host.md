# ADR 0005: URL Validation — Scheme Allowlist and Hostname Blocklist

**Date:** 2026-03-15
**Status:** Accepted

## Context

A security review identified two SSRF vectors:

**S3 / A1 (scheme):** `Perchfall.run(url: "file:///etc/passwd")` would cause Playwright to read local files. `ftp://`, `javascript:`, and `data:` URIs present similar risks. No validation existed.

**A1 (internal addresses):** `Perchfall.run(url: "http://169.254.169.254/")` would cause Playwright to navigate to the AWS instance metadata endpoint. Any `http://` or `https://` URL targeting loopback, link-local, or RFC-1918 addresses could be used to probe the internal network.

## Decision

`UrlValidator` is introduced as a dedicated class, injected into `Client`. It enforces two rules in sequence:

**Rule 1 — Scheme allowlist.** Only `http` and `https` are permitted. Anything else (`file`, `ftp`, `javascript`, `data`, bare strings, unparseable strings) raises `ArgumentError` before any process is spawned.

**Rule 2 — Hostname blocklist (literal addresses only).** The following are rejected:

| Range | Coverage |
|---|---|
| `localhost` | Hostname literal |
| `127.0.0.0/8` | Full IPv4 loopback range |
| `::1` | IPv6 loopback |
| `169.254.0.0/16` | Link-local, incl. AWS metadata (`169.254.169.254`) |
| `fe80::/10` | IPv6 link-local |
| `10.0.0.0/8` | RFC-1918 |
| `172.16.0.0/12` | RFC-1918 |
| `192.168.0.0/16` | RFC-1918 |
| `0.0.0.0/8` | Unroutable |

`IPAddr` range checks cover the full CIDR block, not just spot addresses.

## Explicit Non-Decision

DNS-based SSRF (a public hostname that resolves to a private IP) is **not** mitigated here. Resolving DNS at validation time introduces a TOCTOU race: Playwright performs its own DNS lookup independently, and the resolution could differ. The correct defence for this attack vector is network-level egress filtering (security groups, firewall rules) on the host running Chromium. This limitation is documented in `UrlValidator`'s source.

## Consequences

- Validation is synchronous and raises `ArgumentError` before any child process is spawned. No browser resources are consumed for invalid URLs.
- `UrlValidator` is injectable at `Client.new(validator:)`, keeping it testable in isolation and replaceable if requirements change (e.g. a future allowlist of specific domains).
- Callers targeting legitimate internal addresses (e.g. a monitoring tool that runs inside a private network and checks internal services) cannot use the default validator. They would need to inject a custom `validator:` or `nil` equivalent — a deliberate friction point.
