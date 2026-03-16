# Security

## URL validation

Perchfall validates URLs before spawning any process:

- **Scheme** must be `http` or `https`. `file://`, `ftp://`, `javascript:`, `data:`, and bare strings are rejected with `ArgumentError`.
- **Host** must not be a known internal address. Blocked ranges: `localhost`, `127.0.0.0/8`, `::1`, `169.254.0.0/16` (including the AWS EC2 metadata endpoint at `169.254.169.254`), `fe80::/10`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, and `0.0.0.0/8`.
- **DNS resolution** — hostnames are resolved before the browser is launched, and all returned addresses are checked against the same blocked ranges. This narrows the DNS rebinding window from arbitrarily wide to the milliseconds between Perchfall's lookup and Playwright's own.

## Defence in depth

The DNS check is a best-effort mitigation, not an authoritative control. A TOCTOU race remains between Perchfall's resolution and Playwright's. **Network-level egress filtering on the host running Chromium is the required authoritative control** for SSRF prevention.

## Ignore rules

Perchfall ships with one default ignore rule: `net::ERR_ABORTED` on any URL. This suppresses noise from analytics beacons and cancelled prefetch requests. Filtered errors are still captured on the report as `ignored_network_errors` and `ignored_console_errors` — nothing is silently dropped.

See [Architecture Decision Records](../doc/adr/) 0005 and 0012 for the full reasoning behind these choices.
