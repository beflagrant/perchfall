# frozen_string_literal: true

module Perchfall
  # Knows how to invoke the Playwright Node script and return a Report.
  #
  # Collaborators (all injectable):
  #   runner      - responds to #call(argv_array) -> Result
  #   parser      - responds to #parse(raw_json, **opts) -> Report
  #   script_path - String path to playwright/check.js
  #
  # PlaywrightInvoker owns the command shape and error-promotion semantics.
  # It does not know how to run a process (runner's job) or parse JSON (parser's job).
  class PlaywrightInvoker
    DEFAULT_SCRIPT_PATH = File.expand_path(
      "../../playwright/check.js",
      __dir__
    ).freeze

    def initialize(
      runner: CommandRunner.new,
      script_path: DEFAULT_SCRIPT_PATH
    )
      @runner      = runner
      @script_path = script_path
    end

    def run(url:, timestamp:, timeout_ms: 30_000, wait_until: "load", scenario_name: nil, ignore: [], original_url: nil)
      parser = build_parser(ignore)
      result = execute(build_command(url: url, timeout_ms: timeout_ms, wait_until: wait_until))
      report = parse(result, parser: parser, scenario_name: scenario_name, timestamp: timestamp, original_url: original_url || url)
      raise_if_page_load_error(report)
      report
    end

    private

    def build_parser(ignore_rules)
      Parsers::PlaywrightJsonParser.new(filter: ErrorFilter.new(rules: ignore_rules))
    end

    def build_command(url:, timeout_ms:, wait_until:)
      ["node", @script_path, "--url", url, "--timeout", timeout_ms.to_s, "--wait-until", wait_until]
    end

    def execute(command)
      @runner.call(command)
    rescue => e
      raise Errors::InvocationError, "Could not start Node process: #{e.message}"
    end

    def parse(result, parser:, **opts)
      unless result.success?
        raise Errors::ScriptError.new(
          "Playwright script exited with status #{result.exit_status}",
          exit_status: result.exit_status,
          stderr:      result.stderr
        )
      end

      parser.parse(result.stdout, **opts)
    end

    def raise_if_page_load_error(report)
      raise Errors::PageLoadError.new(report) unless report.ok?
    end
  end
end
