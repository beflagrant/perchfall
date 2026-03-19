#!/usr/bin/env node
// playwright/check.js
//
// Runs a single synthetic check against a URL using Playwright.
// Writes one JSON object to stdout; exits 0 when JSON is trustworthy,
// exits 1 only for infrastructure failures (Node crash, missing args) where
// stdout cannot be trusted.
//
// Usage:
//   node playwright/check.js --url https://example.com --timeout 30000

"use strict";

const { chromium } = require("playwright");
const { parseArgs } = require("node:util");

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

const { values: args } = parseArgs({
  options: {
    url:        { type: "string" },
    timeout:    { type: "string", default: "30000" },
    "wait-until": { type: "string", default: "load" },
    headers:    { type: "string", default: "{}" },
  },
  strict: true,
});

if (!args.url) {
  process.stderr.write("Error: --url is required\n");
  process.exit(1);
}

const TARGET_URL = args.url;
const TIMEOUT_MS = parseInt(args.timeout, 10);
const WAIT_UNTIL = args["wait-until"];

let EXTRA_HEADERS;
try {
  const parsed = JSON.parse(args.headers);
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new TypeError("--headers must be a JSON object, got: " + args.headers);
  }
  for (const [key, value] of Object.entries(parsed)) {
    if (typeof value !== "string") {
      throw new TypeError(`--headers value for "${key}" must be a string, got ${typeof value}`);
    }
  }
  EXTRA_HEADERS = parsed;
} catch (err) {
  process.stdout.write(JSON.stringify({
    status:         "error",
    url:            TARGET_URL,
    duration_ms:    0,
    http_status:    null,
    network_errors: [],
    console_errors: [],
    error:          "Invalid --headers: " + err.message,
  }));
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildResult({ status, durationMs, httpStatus, networkErrors, consoleErrors, error }) {
  return JSON.stringify({
    status,
    url:            TARGET_URL,
    duration_ms:    durationMs,
    http_status:    httpStatus  ?? null,
    network_errors: networkErrors,
    console_errors: consoleErrors,
    error:          error ?? null,
  });
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function run() {
  const startedAt      = Date.now();
  const networkErrors  = [];
  const consoleErrors  = [];
  let   browser;

  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();

    if (Object.keys(EXTRA_HEADERS).length > 0) {
      await page.setExtraHTTPHeaders(EXTRA_HEADERS);
    }

    // Collect failed network requests (4xx/5xx responses + connection failures).
    page.on("requestfailed", (request) => {
      networkErrors.push({
        url:     request.url(),
        method:  request.method(),
        failure: request.failure()?.errorText ?? "unknown",
      });
    });

    // Collect non-2xx/3xx responses as network errors too.
    page.on("response", (response) => {
      const status = response.status();
      if (status >= 400) {
        networkErrors.push({
          url:     response.url(),
          method:  response.request().method(),
          failure: `HTTP ${status}`,
        });
      }
    });

    // Collect browser console errors.
    page.on("console", (msg) => {
      if (msg.type() === "error") {
        const loc = msg.location();
        consoleErrors.push({
          type:     msg.type(),
          text:     msg.text(),
          location: loc ? `${loc.url}:${loc.lineNumber}:${loc.columnNumber}` : "",
        });
      }
    });

    const response = await page.goto(TARGET_URL, {
      timeout:   TIMEOUT_MS,
      waitUntil: WAIT_UNTIL,
    });

    const durationMs = Date.now() - startedAt;

    process.stdout.write(buildResult({
      status:        "ok",
      durationMs,
      httpStatus:    response ? response.status() : null,
      networkErrors,
      consoleErrors,
      error:         null,
    }));

    process.exit(0);

  } catch (err) {
    // Page-level failure (timeout, DNS, etc.) — exit 0 so Ruby reads the JSON.
    const durationMs = Date.now() - startedAt;

    process.stdout.write(buildResult({
      status:        "error",
      durationMs,
      httpStatus:    null,
      networkErrors,
      consoleErrors,
      error:         err.message,
    }));

    process.exit(0);

  } finally {
    if (browser) await browser.close().catch(() => {});
  }
}

// Infrastructure-level failure — stdout cannot be trusted, exit 1.
run().catch((err) => {
  process.stderr.write(`Unhandled error: ${err.stack ?? err.message}\n`);
  process.exit(1);
});
