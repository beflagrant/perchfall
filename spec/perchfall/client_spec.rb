# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::Client do
  include ReportFactory

  # A minimal fake invoker — returns a canned report, records call args.
  let(:recording_invoker) do
    Class.new do
      attr_reader :last_url, :last_opts

      def run(url:, **opts)
        @last_url  = url
        @last_opts = opts
        Perchfall::Report.new(
          status: "ok", url: url, duration_ms: 1,
          http_status: 200, network_errors: [], console_errors: [], error: nil
        )
      end
    end.new
  end

  subject(:client) { described_class.new(invoker: recording_invoker) }

  it "delegates run to the invoker with the given url" do
    client.run(url: "https://example.com")
    expect(recording_invoker.last_url).to eq("https://example.com")
  end

  it "forwards keyword options to the invoker" do
    client.run(url: "https://example.com", timeout_ms: 9_000, scenario_name: "smoke")
    expect(recording_invoker.last_opts).to eq({ timeout_ms: 9_000, scenario_name: "smoke" })
  end

  it "returns the report from the invoker" do
    report = client.run(url: "https://example.com")
    expect(report).to be_a(Perchfall::Report)
    expect(report.url).to eq("https://example.com")
  end

  it "propagates exceptions from the invoker unchanged" do
    raising_invoker = Class.new do
      def run(url:, **) = raise Perchfall::Errors::InvocationError, "node not found"
    end.new

    client = described_class.new(invoker: raising_invoker)
    expect { client.run(url: "https://example.com") }
      .to raise_error(Perchfall::Errors::InvocationError, "node not found")
  end
end
