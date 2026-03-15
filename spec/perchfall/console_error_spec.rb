# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::ConsoleError do
  subject(:ce) { described_class.new(type: "error", text: "Uncaught ReferenceError: foo", location: "https://example.com/app.js:10:5") }

  it "is frozen" do
    expect(ce).to be_frozen
  end

  it "exposes type, text, location" do
    expect(ce.type).to eq("error")
    expect(ce.text).to eq("Uncaught ReferenceError: foo")
    expect(ce.location).to eq("https://example.com/app.js:10:5")
  end

  it "has value equality" do
    other = described_class.new(type: "error", text: "Uncaught ReferenceError: foo", location: "https://example.com/app.js:10:5")
    expect(ce).to eq(other)
  end

  it "serializes to a plain hash via to_h" do
    expect(ce.to_h).to eq({
      type:     "error",
      text:     "Uncaught ReferenceError: foo",
      location: "https://example.com/app.js:10:5"
    })
  end

  it "round-trips through to_json / JSON.parse" do
    parsed = JSON.parse(ce.to_json)
    expect(parsed["type"]).to eq("error")
    expect(parsed["text"]).to eq("Uncaught ReferenceError: foo")
  end
end
