# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::CommandRunner do
  subject(:runner) { described_class.new }

  it "returns a successful result for a zero-exit command" do
    result = runner.call(["echo", "hello"])
    expect(result.stdout.strip).to eq("hello")
    expect(result.exit_status).to eq(0)
    expect(result).to be_success
  end

  it "captures stderr and non-zero exit" do
    result = runner.call(["bash", "-c", "echo fail >&2; exit 42"])
    expect(result.stderr.strip).to eq("fail")
    expect(result.exit_status).to eq(42)
    expect(result).not_to be_success
  end

  it "captures stdout and stderr simultaneously" do
    result = runner.call(["bash", "-c", "echo out; echo err >&2"])
    expect(result.stdout.strip).to eq("out")
    expect(result.stderr.strip).to eq("err")
  end

  describe "Result" do
    it "is frozen" do
      result = runner.call(["true"])
      expect(result).to be_frozen
    end
  end
end
