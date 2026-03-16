# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::Report do
  include ReportFactory

  describe "immutability" do
    it "is frozen after construction" do
      expect(build_report).to be_frozen
    end

    it "freezes network_errors array" do
      ne = Perchfall::NetworkError.new(url: "https://cdn.example.com/x.js", method: "GET", failure: "timeout")
      report = build_report(network_errors: [ne])
      expect(report.network_errors).to be_frozen
    end

    it "freezes ignored_network_errors array" do
      ne = Perchfall::NetworkError.new(url: "https://cdn.example.com/x.js", method: "GET", failure: "timeout")
      report = build_report(ignored_network_errors: [ne])
      expect(report.ignored_network_errors).to be_frozen
    end
  end

  describe "#ok?" do
    it "returns true when status is 'ok'" do
      expect(build_report(status: "ok")).to be_ok
    end

    it "returns false when status is 'error'" do
      expect(build_report(status: "error", error: "timeout")).not_to be_ok
    end
  end

  describe "#to_h" do
    it "includes all top-level keys" do
      h = build_report.to_h
      expect(h.keys).to contain_exactly(
        :status, :url, :scenario_name, :timestamp, :ok,
        :http_status, :duration_ms, :network_errors, :ignored_network_errors, :console_errors, :error
      )
    end

    it "serializes ignored_network_errors as plain hashes" do
      ne = Perchfall::NetworkError.new(url: "https://shop.app/pay", method: "GET", failure: "HTTP 403")
      report = build_report(ignored_network_errors: [ne])
      expect(report.to_h[:ignored_network_errors]).to eq([
        { url: "https://shop.app/pay", method: "GET", failure: "HTTP 403" }
      ])
    end

    it "serializes network_errors as plain hashes" do
      ne = Perchfall::NetworkError.new(url: "https://cdn.example.com/x.js", method: "GET", failure: "timeout")
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
  end
end
