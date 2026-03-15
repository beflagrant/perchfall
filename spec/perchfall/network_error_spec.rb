# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::NetworkError do
  subject(:ne) { described_class.new(url: "https://cdn.example.com/app.js", method: "GET", failure: "net::ERR_ABORTED") }

  it "is frozen" do
    expect(ne).to be_frozen
  end

  it "exposes url, method, failure" do
    expect(ne.url).to eq("https://cdn.example.com/app.js")
    expect(ne.method).to eq("GET")
    expect(ne.failure).to eq("net::ERR_ABORTED")
  end

  it "has value equality" do
    other = described_class.new(url: "https://cdn.example.com/app.js", method: "GET", failure: "net::ERR_ABORTED")
    expect(ne).to eq(other)
  end

  it "serializes to a plain hash via to_h" do
    expect(ne.to_h).to eq({
      url:     "https://cdn.example.com/app.js",
      method:  "GET",
      failure: "net::ERR_ABORTED"
    })
  end

  it "round-trips through to_json / JSON.parse" do
    parsed = JSON.parse(ne.to_json)
    expect(parsed).to eq({
      "url"     => "https://cdn.example.com/app.js",
      "method"  => "GET",
      "failure" => "net::ERR_ABORTED"
    })
  end
end
