# frozen_string_literal: true

module Perchfall
  module Errors
    # Base for all Perchfall errors. Rescue this to catch anything from the gem.
    class Error < StandardError; end

    # The Node/Playwright process could not be started.
    # Cause: Node not installed, script path wrong, etc.
    class InvocationError < Error; end

    # The Node process ran but exited non-zero, or produced unparseable output.
    class ScriptError < Error
      attr_reader :exit_status, :stderr

      def initialize(message, exit_status: nil, stderr: nil)
        super(message)
        @exit_status = exit_status
        @stderr      = stderr
      end
    end

    # The JSON the Node script produced was structurally invalid.
    class ParseError < Error; end

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
