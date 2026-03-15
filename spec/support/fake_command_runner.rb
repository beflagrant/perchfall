# frozen_string_literal: true

# A test fake for Perchfall::CommandRunner.
#
# Using a real Ruby class (not an RSpec double) avoids coupling tests to
# internal method names and makes the interface contract explicit.
# Matches the Result interface: stdout, stderr, exit_status, success?.
class FakeCommandRunner
  Result = Struct.new(:stdout, :stderr, :exit_status, keyword_init: true) do
    def success?
      exit_status.zero?
    end
  end

  attr_reader :last_command

  def initialize(stdout: "{}", stderr: "", exit_status: 0)
    @stdout      = stdout
    @stderr      = stderr
    @exit_status = exit_status
  end

  def call(command)
    @last_command = command
    Result.new(stdout: @stdout, stderr: @stderr, exit_status: @exit_status)
  end
end
