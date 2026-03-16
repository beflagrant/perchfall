# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::Parsers::PlaywrightJsonParser do
  include PlaywrightJsonFixture

  subject(:parser) { described_class.new }

  let(:fixed_time) { Time.utc(2026, 3, 15, 21, 30, 0) }

  describe "#parse" do
    context "with a valid ok payload" do
      it "returns a Report" do
        report = parser.parse(ok_json)
        expect(report).to be_a(Perchfall::Report)
      end

      it "maps status, url, duration_ms, http_status" do
        report = parser.parse(ok_json)
        expect(report.status).to eq("ok")
        expect(report.url).to eq("https://example.com")
        expect(report.duration_ms).to eq(512)
        expect(report.http_status).to eq(200)
      end

      it "returns an ok? report" do
        expect(parser.parse(ok_json)).to be_ok
      end

      it "accepts an injected timestamp" do
        report = parser.parse(ok_json, timestamp: fixed_time)
        expect(report.timestamp).to eq(fixed_time)
      end

      it "accepts a scenario_name" do
        report = parser.parse(ok_json, scenario_name: "homepage_smoke")
        expect(report.scenario_name).to eq("homepage_smoke")
      end
    end

    context "with network_errors in the payload" do
      let(:real_failure_entry) { network_error_entry(failure: "net::ERR_NAME_NOT_RESOLVED") }
      let(:json) { ok_json(network_errors: [real_failure_entry]) }

      it "parses into NetworkError objects" do
        report = parser.parse(json)
        expect(report.network_errors.length).to eq(1)
        expect(report.network_errors.first).to be_a(Perchfall::NetworkError)
      end

      it "maps url, method, failure" do
        ne = parser.parse(json).network_errors.first
        expect(ne.url).to eq("https://example.com/app.js")
        expect(ne.method).to eq("GET")
        expect(ne.failure).to eq("net::ERR_NAME_NOT_RESOLVED")
      end
    end

    context "with ERR_ABORTED network errors (browser-aborted requests)" do
      it "excludes ERR_ABORTED entries from network_errors" do
        aborted_entry = network_error_entry(failure: "net::ERR_ABORTED")
        json = ok_json(network_errors: [aborted_entry])
        report = parser.parse(json)
        expect(report.network_errors).to be_empty
      end

      it "keeps real failures alongside aborted ones" do
        aborted  = network_error_entry(failure: "net::ERR_ABORTED")
        real     = network_error_entry(url: "https://example.com/api.js", failure: "net::ERR_CONNECTION_REFUSED")
        json     = ok_json(network_errors: [aborted, real])
        report   = parser.parse(json)
        expect(report.network_errors.length).to eq(1)
        expect(report.network_errors.first.failure).to eq("net::ERR_CONNECTION_REFUSED")
      end

      it "returns an empty array when all errors are ERR_ABORTED" do
        entries = [
          network_error_entry(url: "https://analytics.google.com/g/collect", failure: "net::ERR_ABORTED"),
          network_error_entry(url: "https://www.google-analytics.com/g/collect", failure: "net::ERR_ABORTED"),
        ]
        json   = ok_json(network_errors: entries)
        report = parser.parse(json)
        expect(report.network_errors).to be_empty
      end
    end

    context "with console_errors in the payload" do
      let(:json) { ok_json(console_errors: [console_error_entry]) }

      it "parses into ConsoleError objects" do
        report = parser.parse(json)
        expect(report.console_errors.length).to eq(1)
        expect(report.console_errors.first).to be_a(Perchfall::ConsoleError)
      end

      it "maps type, text, location" do
        ce = parser.parse(json).console_errors.first
        expect(ce.type).to eq("error")
        expect(ce.text).to eq("Uncaught ReferenceError: foo is not defined")
        expect(ce.location).to eq("https://example.com/app.js:10:5")
      end
    end

    context "with a valid error payload" do
      it "returns a non-ok report" do
        report = parser.parse(error_json)
        expect(report).not_to be_ok
        expect(report.error).to eq("net::ERR_NAME_NOT_RESOLVED")
        expect(report.http_status).to be_nil
      end
    end

    context "with invalid JSON" do
      it "raises ParseError" do
        expect { parser.parse("not json at all") }
          .to raise_error(Perchfall::Errors::ParseError, /Invalid JSON/)
      end
    end

    context "with missing required field" do
      it "raises ParseError naming the field" do
        json = { status: "ok" }.to_json  # missing url, duration_ms, etc.
        expect { parser.parse(json) }
          .to raise_error(Perchfall::Errors::ParseError, /missing required field/)
      end
    end

    context "with a malformed network_error entry" do
      it "raises ParseError" do
        json = ok_json(network_errors: [{ url: "https://x.com" }])  # missing method, failure
        expect { parser.parse(json) }
          .to raise_error(Perchfall::Errors::ParseError, /Malformed network_error/)
      end
    end

    context "with a malformed console_error entry" do
      it "raises ParseError" do
        json = ok_json(console_errors: [{ text: "boom" }])  # missing type, location
        expect { parser.parse(json) }
          .to raise_error(Perchfall::Errors::ParseError, /Malformed console_error/)
      end
    end
  end
end
