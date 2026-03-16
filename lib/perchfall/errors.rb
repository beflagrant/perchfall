# frozen_string_literal: true

module Perchfall
  module Errors
    # Base for all Perchfall errors. Rescue this to catch anything from the gem.
    class Error < StandardError; end

    # The Node/Playwright process could not be started.
    # Cause: Node not installed, script path wrong, etc.
    class InvocationError < Error; end

    # The Node process ran but exited non-zero, or produced unparseable output.
    # exit_status is exposed for callers that need to distinguish failure modes.
    # stderr is intentionally not public — it may contain server filesystem paths,
    # Node version strings, and stack traces that should not be surfaced to end users.
    # Log stderr at the framework/application level using a rescue block if needed.
    class ScriptError < Error
      attr_reader :exit_status

      def initialize(message, exit_status: nil, stderr: nil)
        super(message)
        @exit_status = exit_status
        @stderr      = stderr
      end

      private

      attr_reader :stderr
    end

    # The JSON the Node script produced was structurally invalid.
    class ParseError < Error; end

    # The concurrency limit was reached and the caller's timeout expired
    # before a slot became available.
    class ConcurrencyLimitError < Error; end

    # The target URL was unreachable at the network/page level (Playwright
    # reported status: "error"). Carries the partial Report so callers can
    # inspect whatever was captured before failure.
    class PageLoadError < Error
      attr_reader :report

      def initialize(report)
        super("Page failed to load: #{report.url} — #{report.error}")
        @report = report
      end
    end
  end
end
