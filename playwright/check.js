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
    url:          { type: "string" },
    timeout:      { type: "string", default: "30000" },
    "wait-until": { type: "string", default: "load" },
    screenshot:   { type: "string", default: "on_error" },
  },
  strict: true,
});

if (!args.url) {
  process.stderr.write("Error: --url is required\n");
  process.exit(1);
}

const TARGET_URL  = args.url;
const TIMEOUT_MS  = parseInt(args.timeout, 10);
const WAIT_UNTIL  = args["wait-until"];
const SCREENSHOT  = args.screenshot; // "always" | "on_error" | "never"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildResult({ status, durationMs, httpStatus, networkErrors, consoleErrors, error, screenshot }) {
  return JSON.stringify({
    status,
    url:            TARGET_URL,
    duration_ms:    durationMs,
    http_status:    httpStatus  ?? null,
    network_errors: networkErrors,
    console_errors: consoleErrors,
    error:          error ?? null,
    screenshots:    screenshot ?? null,
  });
}

async function captureScreenshot(page) {
  const buffer = await page.screenshot({ type: "png" });
  return buffer.toString("base64");
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
    const screenshot = SCREENSHOT === "always" ? await captureScreenshot(page) : null;

    process.stdout.write(buildResult({
      status:        "ok",
      durationMs,
      httpStatus:    response ? response.status() : null,
      networkErrors,
      consoleErrors,
      error:         null,
      screenshot,
    }));

    process.exit(0);

  } catch (err) {
    // Page-level failure (timeout, DNS, etc.) — exit 0 so Ruby reads the JSON.
    const durationMs = Date.now() - startedAt;
    const screenshot = SCREENSHOT === "always" || SCREENSHOT === "on_error"
      ? await captureScreenshot(page).catch(() => null)
      : null;

    process.stdout.write(buildResult({
      status:        "error",
      durationMs,
      httpStatus:    null,
      networkErrors,
      consoleErrors,
      error:         err.message,
      screenshot,
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
