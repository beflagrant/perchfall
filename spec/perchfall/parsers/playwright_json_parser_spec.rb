# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::Parsers::PlaywrightJsonParser do
  include PlaywrightJsonFixture

  let(:aborted_rule)   { Perchfall::IgnoreRule.new(pattern: //, type: "net::ERR_ABORTED", target: :network) }
  let(:ref_error_rule) { Perchfall::IgnoreRule.new(pattern: "ReferenceError", type: "error", target: :console) }

  subject(:parser) { described_class.new }

  let(:fixed_time) { Time.utc(2026, 3, 15, 21, 30, 0) }

  describe "#parse" do
    context "with a valid ok payload" do
      it "returns a Report" do
        expect(parser.parse(ok_json, timestamp: fixed_time)).to be_a(Perchfall::Report)
      end

      it "maps status, url, duration_ms, http_status" do
        report = parser.parse(ok_json, timestamp: fixed_time)
        expect(report.status).to eq("ok")
        expect(report.url).to eq("https://example.com")
        expect(report.duration_ms).to eq(512)
        expect(report.http_status).to eq(200)
      end

      it "returns an ok? report" do
        expect(parser.parse(ok_json, timestamp: fixed_time)).to be_ok
      end

      it "uses the provided timestamp" do
        report = parser.parse(ok_json, timestamp: fixed_time)
        expect(report.timestamp).to eq(fixed_time)
      end

      it "accepts a scenario_name" do
        report = parser.parse(ok_json, timestamp: fixed_time, scenario_name: "homepage_smoke")
        expect(report.scenario_name).to eq("homepage_smoke")
      end

      it "requires timestamp to be provided" do
        expect { parser.parse(ok_json) }
          .to raise_error(ArgumentError, /timestamp/)
      end
    end

    context "with network_errors in the payload" do
      let(:real_failure_entry) { network_error_entry(failure: "net::ERR_NAME_NOT_RESOLVED") }
      let(:json) { ok_json(network_errors: [real_failure_entry]) }

      it "parses into NetworkError objects" do
        report = parser.parse(json, timestamp: fixed_time)
        expect(report.network_errors.length).to eq(1)
        expect(report.network_errors.first).to be_a(Perchfall::NetworkError)
      end

      it "maps url, http_method, failure" do
        ne = parser.parse(json, timestamp: fixed_time).network_errors.first
        expect(ne.url).to eq("https://example.com/app.js")
        expect(ne.http_method).to eq("GET")
        expect(ne.failure).to eq("net::ERR_NAME_NOT_RESOLVED")
      end
    end

    context "with console_errors in the payload" do
      let(:json) { ok_json(console_errors: [console_error_entry]) }

      it "parses into ConsoleError objects" do
        report = parser.parse(json, timestamp: fixed_time)
        expect(report.console_errors.length).to eq(1)
        expect(report.console_errors.first).to be_a(Perchfall::ConsoleError)
      end

      it "maps type, text, location" do
        ce = parser.parse(json, timestamp: fixed_time).console_errors.first
        expect(ce.type).to eq("error")
        expect(ce.text).to eq("Uncaught ReferenceError: foo is not defined")
        expect(ce.location).to eq("https://example.com/app.js:10:5")
      end
    end

    context "with no filter (default)" do
      it "puts all network_errors in network_errors and none in ignored" do
        json   = ok_json(network_errors: [network_error_entry(failure: "net::ERR_ABORTED")])
        report = parser.parse(json, timestamp: fixed_time)
        expect(report.network_errors.length).to eq(1)
        expect(report.ignored_network_errors).to be_empty
      end

      it "puts all console_errors in console_errors and none in ignored" do
        json   = ok_json(console_errors: [console_error_entry])
        report = parser.parse(json, timestamp: fixed_time)
        expect(report.console_errors.length).to eq(1)
        expect(report.ignored_console_errors).to be_empty
      end
    end

    context "with an injected ErrorFilter" do
      subject(:parser) do
        described_class.new(filter: Perchfall::ErrorFilter.new(rules: [aborted_rule, ref_error_rule]))
      end

      it "moves ERR_ABORTED network errors to ignored_network_errors" do
        json   = ok_json(network_errors: [network_error_entry(failure: "net::ERR_ABORTED")])
        report = parser.parse(json, timestamp: fixed_time)
        expect(report.network_errors).to be_empty
        expect(report.ignored_network_errors.first.failure).to eq("net::ERR_ABORTED")
      end

      it "keeps real network failures in network_errors" do
        aborted = network_error_entry(failure: "net::ERR_ABORTED")
        real    = network_error_entry(url: "https://example.com/api.js", failure: "net::ERR_CONNECTION_REFUSED")
        report  = parser.parse(ok_json(network_errors: [aborted, real]), timestamp: fixed_time)
        expect(report.network_errors.map(&:failure)).to eq(["net::ERR_CONNECTION_REFUSED"])
        expect(report.ignored_network_errors.map(&:failure)).to eq(["net::ERR_ABORTED"])
      end

      it "moves matched console errors to ignored_console_errors" do
        json   = ok_json(console_errors: [console_error_entry])
        report = parser.parse(json, timestamp: fixed_time)
        expect(report.console_errors).to be_empty
        expect(report.ignored_console_errors.first.text).to eq("Uncaught ReferenceError: foo is not defined")
      end

      it "keeps unmatched console errors in console_errors" do
        unmatched = console_error_entry(text: "SyntaxError: unexpected token")
        report    = parser.parse(ok_json(console_errors: [console_error_entry, unmatched]), timestamp: fixed_time)
        expect(report.console_errors.map(&:text)).to eq(["SyntaxError: unexpected token"])
        expect(report.ignored_console_errors.map(&:text)).to eq(["Uncaught ReferenceError: foo is not defined"])
      end
    end

    context "with resources in the payload" do
      context "when capture_resources is false (default)" do
        it "returns an empty resources array regardless of payload content" do
          json   = ok_json(resources: [resource_entry])
          report = parser.parse(json, timestamp: fixed_time)
          expect(report.resources).to be_empty
        end
      end

      context "when capture_resources is true" do
        it "returns resources above the threshold" do
          big = resource_entry(transfer_size: 300_000)
          json = ok_json(resources: [big])
          report = parser.parse(json, timestamp: fixed_time, capture_resources: true, large_resource_threshold_bytes: 200_000)
          expect(report.resources.length).to eq(1)
          expect(report.resources.first).to be_a(Perchfall::Resource)
        end

        it "excludes resources below the threshold" do
          small = resource_entry(transfer_size: 10_000)
          json  = ok_json(resources: [small])
          report = parser.parse(json, timestamp: fixed_time, capture_resources: true, large_resource_threshold_bytes: 200_000)
          expect(report.resources).to be_empty
        end

        it "includes resources with nil transfer_size (unknown, cannot prove small)" do
          unknown = resource_entry(transfer_size: nil)
          json = ok_json(resources: [unknown])
          report = parser.parse(json, timestamp: fixed_time, capture_resources: true, large_resource_threshold_bytes: 200_000)
          expect(report.resources.length).to eq(1)
          expect(report.resources.first.transfer_size).to be_nil
        end

        it "maps all Resource fields correctly" do
          entry = resource_entry(
            url: "https://example.com/bg.png", method: "GET", status: 200,
            content_type: "image/png", transfer_size: 500_000, resource_type: "image"
          )
          report = parser.parse(ok_json(resources: [entry]), timestamp: fixed_time,
                                capture_resources: true, large_resource_threshold_bytes: 200_000)
          r = report.resources.first
          expect(r.url).to eq("https://example.com/bg.png")
          expect(r.http_method).to eq("GET")
          expect(r.status).to eq(200)
          expect(r.content_type).to eq("image/png")
          expect(r.transfer_size).to eq(500_000)
          expect(r.resource_type).to eq("image")
        end

        it "returns empty array when resources key is absent (backwards compat)" do
          report = parser.parse(ok_json, timestamp: fixed_time, capture_resources: true, large_resource_threshold_bytes: 200_000)
          expect(report.resources).to be_empty
        end

        it "uses the default threshold of 200_000 bytes when not specified" do
          above = resource_entry(transfer_size: 200_001)
          below = resource_entry(url: "https://example.com/small.png", transfer_size: 199_999)
          json  = ok_json(resources: [above, below])
          report = parser.parse(json, timestamp: fixed_time, capture_resources: true)
          expect(report.resources.map(&:transfer_size)).to eq([200_001])
        end
      end
    end

    context "with a valid error payload" do
      it "returns a non-ok report" do
        report = parser.parse(error_json, timestamp: fixed_time)
        expect(report).not_to be_ok
        expect(report.error).to eq("net::ERR_NAME_NOT_RESOLVED")
        expect(report.http_status).to be_nil
      end
    end

    context "with invalid JSON" do
      it "raises ParseError" do
        expect { parser.parse("not json at all", timestamp: fixed_time) }
          .to raise_error(Perchfall::Errors::ParseError, /Invalid JSON/)
      end
    end

    context "with missing required field" do
      it "raises ParseError naming the field" do
        json = { status: "ok" }.to_json
        expect { parser.parse(json, timestamp: fixed_time) }
          .to raise_error(Perchfall::Errors::ParseError, /missing required field/)
      end
    end

    context "with a malformed network_error entry" do
      it "raises ParseError" do
        json = ok_json(network_errors: [{ url: "https://x.com" }])
        expect { parser.parse(json, timestamp: fixed_time) }
          .to raise_error(Perchfall::Errors::ParseError, /Malformed network_error/)
      end
    end

    context "with a malformed console_error entry" do
      it "raises ParseError" do
        json = ok_json(console_errors: [{ text: "boom" }])
        expect { parser.parse(json, timestamp: fixed_time) }
          .to raise_error(Perchfall::Errors::ParseError, /Malformed console_error/)
      end
    end
  end
end
