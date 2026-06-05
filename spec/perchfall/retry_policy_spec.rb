# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::RetryPolicy do
  def report(status: "ok", network_errors: [], console_errors: [], error: nil)
    Perchfall::Report.new(
      status: status, url: "https://example.com", duration_ms: 1,
      http_status: status == "ok" ? 200 : nil,
      network_errors: network_errors, console_errors: console_errors, error: error
    )
  end

  def net_error(failure)
    Perchfall::NetworkError.new(url: "https://example.com/a", http_method: "GET", failure: failure)
  end

  def console_error
    Perchfall::ConsoleError.new(type: "error", text: "boom", location: "")
  end

  describe ".reasons_for" do
    it "is empty for an ok report" do
      expect(described_class.reasons_for(report)).to be_empty
    end

    it "flags :load_error for a status:error report" do
      expect(described_class.reasons_for(report(status: "error", error: "net::ERR_TIMED_OUT")))
        .to eq([:load_error])
    end

    it "classifies HTTP 5xx as :server_error" do
      r = report(network_errors: [net_error("HTTP 503")])
      expect(described_class.reasons_for(r)).to eq([:server_error])
    end

    it "classifies HTTP 4xx as :client_error" do
      r = report(network_errors: [net_error("HTTP 404")])
      expect(described_class.reasons_for(r)).to eq([:client_error])
    end

    it "classifies a bare net::ERR_* failure as :network_error" do
      r = report(network_errors: [net_error("net::ERR_CONNECTION_RESET")])
      expect(described_class.reasons_for(r)).to eq([:network_error])
    end

    it "flags :assertion for console errors" do
      r = report(network_errors: [], console_errors: [console_error])
      expect(described_class.reasons_for(r)).to eq([:assertion])
    end

    it "collects every distinct reason and dedupes" do
      r = report(
        status: "error", error: "net::ERR_TIMED_OUT",
        network_errors: [net_error("HTTP 503"), net_error("HTTP 502")],
        console_errors: [console_error]
      )
      expect(described_class.reasons_for(r)).to contain_exactly(:load_error, :server_error, :assertion)
    end

    it "maps ScriptError to :script_error" do
      expect(described_class.reasons_for(Perchfall::Errors::ScriptError.new("boom")))
        .to eq([:script_error])
    end

    it "does not map other exceptions to any reason" do
      expect(described_class.reasons_for(Perchfall::Errors::InvocationError.new("no node"))).to be_empty
    end
  end

  describe ".retryable? with declared symbols" do
    it "is false for an ok report" do
      expect(described_class.retryable?(report, [:load_error])).to be(false)
    end

    it "retries a 5xx-only report when :server_error is declared" do
      r = report(network_errors: [net_error("HTTP 503")])
      expect(described_class.retryable?(r, [:server_error])).to be(true)
    end

    it "does NOT retry a 5xx report that also has a console error" do
      r = report(network_errors: [net_error("HTTP 503")], console_errors: [console_error])
      expect(described_class.retryable?(r, [:server_error])).to be(false)
    end

    it "does NOT retry when a reason is not opted in" do
      r = report(status: "error", error: "net::ERR_TIMED_OUT")
      expect(described_class.retryable?(r, [:server_error])).to be(false)
    end

    it "retries only when EVERY reason is opted in" do
      r = report(status: "error", error: "net::ERR_TIMED_OUT", network_errors: [net_error("HTTP 503")])
      expect(described_class.retryable?(r, [:load_error])).to be(false)
      expect(described_class.retryable?(r, [:load_error, :server_error])).to be(true)
    end

    it "never retries a report whose only failure is a console error" do
      r = report(console_errors: [console_error])
      expect(described_class.retryable?(r, Perchfall::RetryPolicy::CONDITIONS)).to be(false)
    end

    it "retries ScriptError when :script_error is declared" do
      expect(described_class.retryable?(Perchfall::Errors::ScriptError.new("x"), [:script_error])).to be(true)
    end

    it "does not retry other exceptions even with all conditions declared" do
      err = Perchfall::Errors::InvocationError.new("no node")
      expect(described_class.retryable?(err, Perchfall::RetryPolicy::CONDITIONS)).to be(false)
    end
  end

  describe ".retryable? with a predicate proc" do
    it "delegates the decision to the proc" do
      r = report(status: "error", error: "net::ERR_TIMED_OUT")
      always = ->(_outcome) { true }
      never  = ->(_outcome) { false }
      expect(described_class.retryable?(r, always)).to be(true)
      expect(described_class.retryable?(r, never)).to be(false)
    end

    it "passes the raw outcome (report or exception) to the proc" do
      seen = []
      probe = ->(outcome) { seen << outcome; false }
      r = report
      described_class.retryable?(r, probe)
      described_class.retryable?(Perchfall::Errors::ScriptError.new("x"), probe)
      expect(seen).to match([r, an_instance_of(Perchfall::Errors::ScriptError)])
    end

    it "coerces a truthy non-boolean proc result to true" do
      expect(described_class.retryable?(report, ->(_o) { "yes" })).to be(true)
    end
  end
end
