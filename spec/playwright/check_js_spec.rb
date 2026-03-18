# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"
require "timeout"

# Integration specs for playwright/check.js.
#
# These tests invoke the Node script directly as a subprocess — no browser is
# launched for most cases. All cases either fail before the browser starts
# (argument errors) or use a URL that Chromium will reject immediately at the
# DNS/connection stage, so they complete quickly without real network I/O.
#
# The entire group is skipped automatically when `node` is not on PATH.
NODE_AVAILABLE = system("node --version > /dev/null 2>&1")

RSpec.describe "playwright/check.js" do
  before(:all) do
    skip "node not available on PATH" unless NODE_AVAILABLE
  end
  SCRIPT = File.expand_path("../../playwright/check.js", __dir__)

  def run_script(*args, timeout: 15)
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
    it "exits 0 and writes valid JSON to stdout when --headers is omitted" do
      result = run_script("--url", "https://0.0.0.0", "--timeout", "2000")
      expect(result[:exit_status]).to eq(0)
      expect { JSON.parse(result[:stdout]) }.not_to raise_error
    end

    it "exits 0 and writes valid JSON to stdout when --headers is an empty object" do
      result = run_script("--url", "https://0.0.0.0", "--timeout", "2000",
                          "--headers", "{}")
      expect(result[:exit_status]).to eq(0)
      expect { JSON.parse(result[:stdout]) }.not_to raise_error
    end

    it "exits 0 and writes a JSON error result when --headers is malformed JSON" do
      result = run_script("--url", "https://0.0.0.0", "--timeout", "2000",
                          "--headers", "not-json")
      expect(result[:exit_status]).to eq(0)
      parsed = JSON.parse(result[:stdout])
      expect(parsed["status"]).to eq("error")
      expect(parsed["error"]).to match(/invalid.*headers|headers.*json|json.*parse/i)
    end

    it "exits 0 and writes a JSON error result when --headers is valid JSON but not an object" do
      result = run_script("--url", "https://0.0.0.0", "--timeout", "2000",
                          "--headers", '"just a string"')
      expect(result[:exit_status]).to eq(0)
      parsed = JSON.parse(result[:stdout])
      expect(parsed["status"]).to eq("error")
    end

    it "exits 0 and writes a JSON error result when --headers contains a non-string value" do
      result = run_script("--url", "https://0.0.0.0", "--timeout", "2000",
                          "--headers", '{"Cache-Control": 42}')
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
      result = run_script("--url", "https://0.0.0.0", "--timeout", "2000")
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
      result = run_script("--url", "https://0.0.0.0", "--timeout", "2000")
      expect(result[:exit_status]).to eq(0)
    end

    it "sets status to 'error' when the page fails to load" do
      expect(parsed["status"]).to eq("error")
    end
  end
end
