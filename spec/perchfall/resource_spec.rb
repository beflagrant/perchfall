# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::Resource do
  subject(:resource) do
    described_class.new(
      url:           "https://example.com/hero.jpg",
      http_method:   "GET",
      status:        200,
      content_type:  "image/jpeg",
      transfer_size: 204_800,
      resource_type: "image"
    )
  end

  it "exposes url" do
    expect(resource.url).to eq("https://example.com/hero.jpg")
  end

  it "exposes http_method" do
    expect(resource.http_method).to eq("GET")
  end

  it "exposes status" do
    expect(resource.status).to eq(200)
  end

  it "exposes content_type" do
    expect(resource.content_type).to eq("image/jpeg")
  end

  it "exposes transfer_size" do
    expect(resource.transfer_size).to eq(204_800)
  end

  it "exposes resource_type" do
    expect(resource.resource_type).to eq("image")
  end

  it "accepts nil transfer_size (unknown size)" do
    r = described_class.new(
      url: "https://example.com/stream", http_method: "GET", status: 200,
      content_type: "text/event-stream", transfer_size: nil, resource_type: "fetch"
    )
    expect(r.transfer_size).to be_nil
  end

  it "accepts nil content_type" do
    r = described_class.new(
      url: "https://example.com/x", http_method: "GET", status: 200,
      content_type: nil, transfer_size: 1024, resource_type: "other"
    )
    expect(r.content_type).to be_nil
  end

  it "is a value object — equal when attributes match" do
    a = described_class.new(url: "https://example.com/a.jpg", http_method: "GET", status: 200,
                            content_type: "image/jpeg", transfer_size: 1024, resource_type: "image")
    b = described_class.new(url: "https://example.com/a.jpg", http_method: "GET", status: 200,
                            content_type: "image/jpeg", transfer_size: 1024, resource_type: "image")
    expect(a).to eq(b)
  end
end
