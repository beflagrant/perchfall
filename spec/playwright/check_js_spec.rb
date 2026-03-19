# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"
require "timeout"

# Integration specs for playwright/check.js.
#
# These tests invoke the Node script directly as a subprocess. They fall into
# two categories:
#
#   - Browser-free: argument validation and invalid --headers cases exit before
#     Chromium is launched. Fast and deterministic.
#   - Browser-required: valid invocations launch Chromium against a
#     connection-refused address (https://0.0.0.0) and wait for it to fail.
#     These use a generous Playwright timeout so they are stable on slow CI.
#
# The entire group is skipped automatically when `node` is not on PATH.
NODE_AVAILABLE = system("node --version > /dev/null 2>&1")

RSpec.describe "playwright/check.js" do
  before(:all) do
    skip "node not available on PATH" unless NODE_AVAILABLE
  end

  SCRIPT = File.expand_path("../../playwright/check.js", __dir__)

  # Playwright navigation timeout for browser-required tests (ms).
  # Generous enough for a slow CI runner to boot Chromium and get a
  # connection-refused failure before the timeout fires.
  BROWSER_TIMEOUT_MS = "10000"

  # Ruby-level process timeout — must exceed BROWSER_TIMEOUT_MS with headroom.
  PROCESS_TIMEOUT_S  = 30

  def run_script(*args, timeout: PROCESS_TIMEOUT_S)
    stdout, stderr, status = nil
    Timeout.timeout(timeout) do
      stdout, stderr, status = Open3.capture3("node", SCRIPT, *args)
    end
    { stdout: stdout, stderr: stderr, exit_status: status.exitstatus }
  end

  # -------------------------------------------------------------------------
  # Argument validation — no browser launched, exits 1
  # -------------------------------------------------------------------------

  describe "argument validation" do
    it "exits 1 and writes to stderr when --url is missing" do
      result = run_script
      expect(result[:exit_status]).to eq(1)
      expect(result[:stderr]).to match(/--url is required/i)
      expect(result[:stdout]).to be_empty
    end

    it "exits 1 and writes to stderr when an unknown flag is passed" do
      result = run_script("--url", "https://example.com", "--bogus-flag", "x")
      expect(result[:exit_status]).to eq(1)
      expect(result[:stderr]).not_to be_empty
      expect(result[:stdout]).to be_empty
    end
  end

  # -------------------------------------------------------------------------
  # --headers argument — S2: malformed JSON must not crash before the handler
  # -------------------------------------------------------------------------

  describe "--headers argument" do
    # These two launch Chromium — use the full browser timeout.
    it "exits 0 and writes valid JSON to stdout when --headers is omitted" do
      result = run_script("--url", "https://0.0.0.0", "--timeout", BROWSER_TIMEOUT_MS)
      expect(result[:exit_status]).to eq(0)
      expect { JSON.parse(result[:stdout]) }.not_to raise_error
    end

    it "exits 0 and writes valid JSON to stdout when --headers is an empty object" do
      result = run_script("--url", "https://0.0.0.0", "--timeout", BROWSER_TIMEOUT_MS,
                          "--headers", "{}")
      expect(result[:exit_status]).to eq(0)
      expect { JSON.parse(result[:stdout]) }.not_to raise_error
    end

    # These three are browser-free: header validation runs before Chromium starts.
    it "exits 0 and writes a JSON error result when --headers is malformed JSON" do
      result = run_script("--url", "https://0.0.0.0", "--headers", "not-json")
      expect(result[:exit_status]).to eq(0)
      parsed = JSON.parse(result[:stdout])
      expect(parsed["status"]).to eq("error")
      expect(parsed["error"]).to match(/invalid.*headers|headers.*json|json.*parse/i)
    end

    it "exits 0 and writes a JSON error result when --headers is valid JSON but not an object" do
      result = run_script("--url", "https://0.0.0.0", "--headers", '"just a string"')
      expect(result[:exit_status]).to eq(0)
      parsed = JSON.parse(result[:stdout])
      expect(parsed["status"]).to eq("error")
    end

    it "exits 0 and writes a JSON error result when --headers contains a non-string value" do
      result = run_script("--url", "https://0.0.0.0", "--headers", '{"Cache-Control": 42}')
      expect(result[:exit_status]).to eq(0)
      parsed = JSON.parse(result[:stdout])
      expect(parsed["status"]).to eq("error")
    end
  end

  # -------------------------------------------------------------------------
  # JSON output shape — contract tests, no browser required
  # -------------------------------------------------------------------------

  describe "JSON output shape" do
    subject(:parsed) do
      result = run_script("--url", "https://0.0.0.0", "--timeout", BROWSER_TIMEOUT_MS)
      JSON.parse(result[:stdout])
    end

    it "includes status" do
      expect(parsed).to have_key("status")
    end

    it "includes url matching the --url argument" do
      expect(parsed["url"]).to eq("https://0.0.0.0")
    end

    it "includes duration_ms as an integer" do
      expect(parsed["duration_ms"]).to be_an(Integer)
    end

    it "includes network_errors as an array" do
      expect(parsed["network_errors"]).to be_an(Array)
    end

    it "includes console_errors as an array" do
      expect(parsed["console_errors"]).to be_an(Array)
    end

    it "includes error key" do
      expect(parsed).to have_key("error")
    end

    it "exits 0 even when the page fails to load" do
      result = run_script("--url", "https://0.0.0.0", "--timeout", BROWSER_TIMEOUT_MS)
      expect(result[:exit_status]).to eq(0)
    end

    it "sets status to 'error' when the page fails to load" do
      expect(parsed["status"]).to eq("error")
    end
  end
end
