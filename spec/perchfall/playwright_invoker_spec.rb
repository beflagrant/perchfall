# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::PlaywrightInvoker do
  include PlaywrightJsonFixture

  let(:fixed_time) { Time.utc(2026, 3, 15, 21, 30, 0) }

  def invoker_with(stdout:, stderr: "", exit_status: 0)
    runner = FakeCommandRunner.new(stdout: stdout, stderr: stderr, exit_status: exit_status)
    described_class.new(runner: runner)
  end

  describe "#run" do
    context "when Playwright succeeds" do
      subject(:invoker) { invoker_with(stdout: ok_json) }

      it "returns a Report" do
        report = invoker.run(url: "https://example.com", timestamp: fixed_time)
        expect(report).to be_a(Perchfall::Report)
      end

      it "returns an ok report" do
        expect(invoker.run(url: "https://example.com", timestamp: fixed_time)).to be_ok
      end

      it "passes scenario_name through to the report" do
        report = invoker.run(url: "https://example.com", timestamp: fixed_time, scenario_name: "smoke")
        expect(report.scenario_name).to eq("smoke")
      end

      it "uses original_url for report.url when provided" do
        report = invoker.run(
          url:          "https://example.com?_pf=123",
          original_url: "https://example.com",
          timestamp:    fixed_time
        )
        expect(report.url).to eq("https://example.com")
      end

      it "falls back to url for report.url when original_url is not provided" do
        report = invoker.run(url: "https://example.com", timestamp: fixed_time)
        expect(report.url).to eq("https://example.com")
      end

      it "passes timestamp through to the report" do
        report = invoker.run(url: "https://example.com", timestamp: fixed_time)
        expect(report.timestamp).to eq(fixed_time)
      end

      it "requires timestamp to be provided" do
        expect { invoker.run(url: "https://example.com") }
          .to raise_error(ArgumentError, /timestamp/)
      end
    end

    context "command construction" do
      it "passes --url and --timeout to node" do
        runner = FakeCommandRunner.new(stdout: ok_json)
        invoker = described_class.new(runner: runner)
        invoker.run(url: "https://example.com", timeout_ms: 5_000, timestamp: fixed_time)
        expect(runner.last_command).to eq([
          "node",
          Perchfall::PlaywrightInvoker::DEFAULT_SCRIPT_PATH,
          "--url", "https://example.com",
          "--timeout", "5000",
          "--wait-until", "load"
        ])
      end

      it "uses the default 30_000 ms timeout when none given" do
        runner = FakeCommandRunner.new(stdout: ok_json)
        invoker = described_class.new(runner: runner)
        invoker.run(url: "https://example.com", timestamp: fixed_time)
        expect(runner.last_command).to include("30000")
      end

      it "appends --headers JSON when extra_headers are provided" do
        runner = FakeCommandRunner.new(stdout: ok_json)
        invoker = described_class.new(runner: runner)
        invoker.run(
          url: "https://example.com", timestamp: fixed_time,
          extra_headers: { "Cache-Control" => "no-cache" }
        )
        idx = runner.last_command.index("--headers")
        expect(idx).not_to be_nil
        expect(runner.last_command[idx + 1]).to eq('{"Cache-Control":"no-cache"}')
      end

      it "omits --headers when extra_headers is empty" do
        runner = FakeCommandRunner.new(stdout: ok_json)
        invoker = described_class.new(runner: runner)
        invoker.run(url: "https://example.com", timestamp: fixed_time, extra_headers: {})
        expect(runner.last_command).not_to include("--headers")
      end

      it "omits --headers when extra_headers is not provided" do
        runner = FakeCommandRunner.new(stdout: ok_json)
        invoker = described_class.new(runner: runner)
        invoker.run(url: "https://example.com", timestamp: fixed_time)
        expect(runner.last_command).not_to include("--headers")
      end

      it "appends --capture-resources when capture_resources is true" do
        runner = FakeCommandRunner.new(stdout: ok_json)
        invoker = described_class.new(runner: runner)
        invoker.run(url: "https://example.com", timestamp: fixed_time, capture_resources: true)
        expect(runner.last_command).to include("--capture-resources")
      end

      it "omits --capture-resources when capture_resources is false (default)" do
        runner = FakeCommandRunner.new(stdout: ok_json)
        invoker = described_class.new(runner: runner)
        invoker.run(url: "https://example.com", timestamp: fixed_time)
        expect(runner.last_command).not_to include("--capture-resources")
      end
    end

    context "when the script exits non-zero" do
      subject(:invoker) { invoker_with(stdout: "", stderr: "ENOENT: node crashed", exit_status: 1) }

      it "raises ScriptError" do
        expect { invoker.run(url: "https://example.com", timestamp: fixed_time) }
          .to raise_error(Perchfall::Errors::ScriptError)
      end

      it "includes exit_status on the exception" do
        invoker.run(url: "https://example.com", timestamp: fixed_time)
      rescue Perchfall::Errors::ScriptError => e
        expect(e.exit_status).to eq(1)
      end

      it "does not expose stderr as a public attribute" do
        invoker.run(url: "https://example.com", timestamp: fixed_time)
      rescue Perchfall::Errors::ScriptError => e
        expect(e).not_to respond_to(:stderr)
      end
    end

    context "when the page fails to load (status: error in JSON)" do
      subject(:invoker) { invoker_with(stdout: error_json) }

      it "returns a Report with status 'error'" do
        report = invoker.run(url: "https://example.com", timestamp: fixed_time)
        expect(report.status).to eq("error")
      end

      it "report carries the error message" do
        report = invoker.run(url: "https://example.com", timestamp: fixed_time)
        expect(report.error).to eq("net::ERR_NAME_NOT_RESOLVED")
      end

      it "report is not ok" do
        report = invoker.run(url: "https://example.com", timestamp: fixed_time)
        expect(report).not_to be_ok
      end
    end

    context "with ignore rules" do
      it "moves matched network errors to ignored_network_errors" do
        rule   = Perchfall::IgnoreRule.new(pattern: "shop.app", type: "HTTP 403", target: :network)
        runner = FakeCommandRunner.new(stdout: ok_json(network_errors: [
          { url: "https://shop.app/pay", method: "GET", failure: "HTTP 403" }
        ]))
        report = described_class.new(runner: runner).run(url: "https://example.com", timestamp: fixed_time, ignore: [rule])
        expect(report.network_errors).to be_empty
        expect(report.ignored_network_errors.first.failure).to eq("HTTP 403")
      end

      it "moves matched console errors to ignored_console_errors" do
        rule   = Perchfall::IgnoreRule.new(pattern: "ReferenceError", type: "error", target: :console)
        runner = FakeCommandRunner.new(stdout: ok_json(console_errors: [console_error_entry]))
        report = described_class.new(runner: runner).run(url: "https://example.com", timestamp: fixed_time, ignore: [rule])
        expect(report.console_errors).to be_empty
        expect(report.ignored_console_errors.first.text).to include("ReferenceError")
      end
    end

    context "with unknown keyword arguments" do
      subject(:invoker) { invoker_with(stdout: ok_json) }

      it "raises ArgumentError" do
        expect { invoker.run(url: "https://example.com", timestamp: fixed_time, timoeut_ms: 5_000) }
          .to raise_error(ArgumentError, /timoeut_ms/)
      end
    end

    context "when Node cannot be started" do
      it "raises InvocationError" do
        exploding_runner = Class.new do
          def call(_command)
            raise Errno::ENOENT, "No such file or directory - node"
          end
        end.new

        invoker = described_class.new(runner: exploding_runner)
        expect { invoker.run(url: "https://example.com", timestamp: fixed_time) }
          .to raise_error(Perchfall::Errors::InvocationError, /Could not start Node process/)
      end
    end
  end
end
