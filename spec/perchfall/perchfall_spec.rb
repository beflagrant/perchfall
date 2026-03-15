# frozen_string_literal: true

require "spec_helper"

# Integration-style spec: exercises the full Ruby stack (Client → PlaywrightInvoker
# → CommandRunner → Parser → Report) by stubbing only the CommandRunner so no
# real Node process is spawned.
RSpec.describe Perchfall do
  include PlaywrightJsonFixture

  describe ".run" do
    let(:fixed_time) { Time.utc(2026, 3, 15, 21, 30, 0) }

    def stub_runner_with(json)
      runner  = FakeCommandRunner.new(stdout: json)
      invoker = Perchfall::PlaywrightInvoker.new(runner: runner)
      allow(Perchfall::Client).to receive(:new)
        .and_return(Perchfall::Client.new(invoker: invoker))
    end

    context "successful check" do
      before { stub_runner_with(ok_json(http_status: 200, duration_ms: 742)) }

      it "returns a Report" do
        report = Perchfall.run(url: "https://example.com")
        expect(report).to be_a(Perchfall::Report)
      end

      it "report is ok" do
        expect(Perchfall.run(url: "https://example.com")).to be_ok
      end

      it "report carries http_status and duration_ms" do
        report = Perchfall.run(url: "https://example.com")
        expect(report.http_status).to eq(200)
        expect(report.duration_ms).to eq(742)
      end
    end

    context "check with network errors" do
      before do
        stub_runner_with(ok_json(
          network_errors: [{ url: "https://example.com/missing.js", method: "GET", failure: "HTTP 404" }]
        ))
      end

      it "report is still ok (sub-resource errors don't fail the check)" do
        report = Perchfall.run(url: "https://example.com")
        expect(report).to be_ok
        expect(report.network_errors.length).to eq(1)
        expect(report.network_errors.first.failure).to eq("HTTP 404")
      end
    end

    context "page load failure" do
      before { stub_runner_with(error_json) }

      it "raises PageLoadError" do
        expect { Perchfall.run(url: "https://example.com") }
          .to raise_error(Perchfall::Errors::PageLoadError)
      end

      it "PageLoadError carries a partial Report" do
        Perchfall.run(url: "https://example.com")
      rescue Perchfall::Errors::PageLoadError => e
        expect(e.report.url).to eq("https://example.com")
        expect(e.report.error).to eq("net::ERR_NAME_NOT_RESOLVED")
      end
    end

    context "Playwright script crashes (exit 1)" do
      before do
        runner  = FakeCommandRunner.new(stdout: "", stderr: "crash", exit_status: 1)
        invoker = Perchfall::PlaywrightInvoker.new(runner: runner)
        allow(Perchfall::Client).to receive(:new)
          .and_return(Perchfall::Client.new(invoker: invoker))
      end

      it "raises ScriptError" do
        expect { Perchfall.run(url: "https://example.com") }
          .to raise_error(Perchfall::Errors::ScriptError)
      end
    end
  end
end
