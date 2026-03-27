# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::Report do
  include ReportFactory

  describe "immutability" do
    it "is frozen after construction" do
      expect(build_report).to be_frozen
    end

    it "freezes network_errors array" do
      ne = Perchfall::NetworkError.new(url: "https://cdn.example.com/x.js", http_method: "GET", failure: "timeout")
      report = build_report(network_errors: [ne])
      expect(report.network_errors).to be_frozen
    end

    it "freezes ignored_network_errors array" do
      ne = Perchfall::NetworkError.new(url: "https://cdn.example.com/x.js", http_method: "GET", failure: "timeout")
      report = build_report(ignored_network_errors: [ne])
      expect(report.ignored_network_errors).to be_frozen
    end

    it "freezes ignored_console_errors array" do
      ce = Perchfall::ConsoleError.new(type: "error", text: "boom", location: "https://example.com:1:1")
      report = build_report(ignored_console_errors: [ce])
      expect(report.ignored_console_errors).to be_frozen
    end
  end

  describe "#ok?" do
    it "returns true when status is 'ok' and there are no errors" do
      expect(build_report(status: "ok")).to be_ok
    end

    it "returns false when status is 'error'" do
      expect(build_report(status: "error", error: "timeout")).not_to be_ok
    end

    it "returns false when there are network errors" do
      ne = Perchfall::NetworkError.new(url: "https://cdn.example.com/x.js", http_method: "GET", failure: "HTTP 404")
      expect(build_report(network_errors: [ne])).not_to be_ok
    end

    it "returns false when there are console errors" do
      ce = Perchfall::ConsoleError.new(type: "error", text: "Uncaught TypeError", location: "app.js:1:1")
      expect(build_report(console_errors: [ce])).not_to be_ok
    end

    it "returns true when errors are present but all ignored" do
      ne = Perchfall::NetworkError.new(url: "https://cdn.example.com/x.js", http_method: "GET", failure: "HTTP 404")
      expect(build_report(network_errors: [], ignored_network_errors: [ne])).to be_ok
    end
  end

  describe "#cache_profile" do
    it "defaults to nil" do
      expect(build_report.cache_profile).to be_nil
    end

    it "stores the provided value" do
      expect(build_report(cache_profile: :no_cache).cache_profile).to eq(:no_cache)
    end
  end

  describe "#to_h" do
    it "includes all top-level keys" do
      h = build_report.to_h
      expect(h.keys).to contain_exactly(
        :status, :url, :scenario_name, :timestamp, :ok,
        :http_status, :duration_ms,
        :network_errors, :ignored_network_errors,
        :console_errors, :ignored_console_errors,
        :error, :cache_profile, :resources
      )
    end

    it "includes cache_profile in to_h" do
      report = build_report(cache_profile: :no_store)
      expect(report.to_h[:cache_profile]).to eq(:no_store)
    end

    it "includes nil cache_profile when not set" do
      expect(build_report.to_h[:cache_profile]).to be_nil
    end

    it "serializes ignored_network_errors as plain hashes" do
      ne = Perchfall::NetworkError.new(url: "https://shop.app/pay", http_method: "GET", failure: "HTTP 403")
      report = build_report(ignored_network_errors: [ne])
      expect(report.to_h[:ignored_network_errors]).to eq([
        { url: "https://shop.app/pay", method: "GET", failure: "HTTP 403" }
      ])
    end

    it "serializes ignored_console_errors as plain hashes" do
      ce = Perchfall::ConsoleError.new(type: "error", text: "boom", location: "https://example.com:10:1")
      report = build_report(ignored_console_errors: [ce])
      expect(report.to_h[:ignored_console_errors]).to eq([
        { type: "error", text: "boom", location: "https://example.com:10:1" }
      ])
    end

    it "serializes network_errors as plain hashes" do
      ne = Perchfall::NetworkError.new(url: "https://cdn.example.com/x.js", http_method: "GET", failure: "timeout")
      report = build_report(network_errors: [ne])
      expect(report.to_h[:network_errors]).to eq([
        { url: "https://cdn.example.com/x.js", method: "GET", failure: "timeout" }
      ])
    end

    it "serializes console_errors as plain hashes" do
      ce = Perchfall::ConsoleError.new(type: "error", text: "boom", location: "https://example.com:10:1")
      report = build_report(console_errors: [ce])
      expect(report.to_h[:console_errors]).to eq([
        { type: "error", text: "boom", location: "https://example.com:10:1" }
      ])
    end

    it "includes scenario_name when provided" do
      report = build_report(scenario_name: "homepage_smoke")
      expect(report.to_h[:scenario_name]).to eq("homepage_smoke")
    end

    it "formats timestamp as ISO 8601" do
      t = Time.utc(2026, 3, 15, 21, 30, 0)
      report = build_report(timestamp: t)
      expect(report.to_h[:timestamp]).to eq("2026-03-15T21:30:00Z")
    end
  end

  describe "#to_json" do
    it "round-trips through JSON.parse" do
      report  = build_report
      parsed  = JSON.parse(report.to_json)
      expect(parsed["status"]).to eq("ok")
      expect(parsed["url"]).to eq("https://example.com")
      expect(parsed["ok"]).to eq(true)
      expect(parsed["network_errors"]).to eq([])
    end
  end

  describe "#resources" do
    it "defaults to an empty array" do
      expect(build_report.resources).to eq([])
    end

    it "stores provided resources" do
      r = Perchfall::Resource.new(url: "https://example.com/hero.jpg", http_method: "GET",
                                  status: 200, content_type: "image/jpeg",
                                  transfer_size: 204_800, resource_type: "image")
      expect(build_report(resources: [r]).resources).to eq([r])
    end

    it "is frozen" do
      expect(build_report.resources).to be_frozen
    end

    it "is not affected by ok?" do
      r = Perchfall::Resource.new(url: "https://example.com/hero.jpg", http_method: "GET",
                                  status: 200, content_type: "image/jpeg",
                                  transfer_size: 5_000_000, resource_type: "image")
      expect(build_report(resources: [r])).to be_ok
    end
  end

  describe "#==" do
    it "is equal to another Report with the same attributes" do
      t = Time.utc(2026, 1, 1)
      a = build_report(timestamp: t)
      b = build_report(timestamp: t)
      expect(a).to eq(b)
    end

    it "is not equal when attributes differ" do
      t = Time.utc(2026, 1, 1)
      a = build_report(timestamp: t, http_status: 200)
      b = build_report(timestamp: t, http_status: 404)
      expect(a).not_to eq(b)
    end

    it "is not equal when cache_profile differs" do
      t = Time.utc(2026, 1, 1)
      a = build_report(timestamp: t, cache_profile: :warm)
      b = build_report(timestamp: t, cache_profile: :no_cache)
      expect(a).not_to eq(b)
    end
  end
end
