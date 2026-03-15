# frozen_string_literal: true

require "open3"

module Perchfall
  # Wraps Open3.capture3 behind an injectable interface.
  #
  # Interface contract (implement this to build a test fake):
  #
  #   result = runner.call(command)
  #   result.stdout      # => String
  #   result.stderr      # => String
  #   result.success?    # => Boolean
  #   result.exit_status # => Integer
  #
  # Always pass argv arrays, never shell strings — this prevents injection.
  class CommandRunner
    Result = Data.define(:stdout, :stderr, :exit_status) do
      def success?
        exit_status.zero?
      end
    end

    def call(command)
      stdout, stderr, status = Open3.capture3(*command)
      Result.new(
        stdout:      stdout,
        stderr:      stderr,
        exit_status: status.exitstatus
      )
    end
  end
end
