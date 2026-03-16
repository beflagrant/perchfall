# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::Errors::ScriptError do
  subject(:error) do
    described_class.new("script failed", exit_status: 1, stderr: "Error: something at /app/check.js:42")
  end

  it "exposes exit_status" do
    expect(error.exit_status).to eq(1)
  end

  it "does not expose stderr as a public attribute" do
    expect(error).not_to respond_to(:stderr)
  end

  it "does not include stderr in the exception message" do
    expect(error.message).not_to include("/app/check.js")
  end
end
