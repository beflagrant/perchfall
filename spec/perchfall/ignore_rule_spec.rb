# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::IgnoreRule do
  describe "#match?" do
    context "with string pattern (substring)" do
      subject(:rule) { described_class.new(pattern: "shop.app/pay", type: "HTTP 403", target: :network) }

      it "matches when pattern is a substring of primary and type matches" do
        expect(rule.match?("https://shop.app/pay?foo=bar", "HTTP 403")).to be true
      end

      it "does not match when primary does not contain the pattern" do
        expect(rule.match?("https://other.com/pay", "HTTP 403")).to be false
      end

      it "does not match when type differs" do
        expect(rule.match?("https://shop.app/pay", "HTTP 500")).to be false
      end
    end

    context "with regex pattern" do
      subject(:rule) { described_class.new(pattern: /google-analytics\.com/, type: "net::ERR_ABORTED", target: :network) }

      it "matches when primary matches the regex and type matches" do
        expect(rule.match?("https://www.google-analytics.com/g/collect", "net::ERR_ABORTED")).to be true
      end

      it "does not match when primary does not match the regex" do
        expect(rule.match?("https://example.com/track", "net::ERR_ABORTED")).to be false
      end
    end

    context "with wildcard type ('*')" do
      subject(:rule) { described_class.new(pattern: "shop.app", type: "*", target: :network) }

      it "matches any type when pattern matches" do
        expect(rule.match?("https://shop.app/pay", "HTTP 403")).to be true
        expect(rule.match?("https://shop.app/pay", "HTTP 500")).to be true
      end

      it "does not match when primary does not match" do
        expect(rule.match?("https://other.com/pay", "HTTP 403")).to be false
      end
    end

    context "with regex type" do
      subject(:rule) { described_class.new(pattern: "example.com", type: /HTTP \d{3}/, target: :network) }

      it "matches when type matches the regex" do
        expect(rule.match?("https://example.com/app.js", "HTTP 403")).to be true
        expect(rule.match?("https://example.com/app.js", "HTTP 500")).to be true
      end

      it "does not match when type does not match the regex" do
        expect(rule.match?("https://example.com/app.js", "net::ERR_ABORTED")).to be false
      end
    end

    context "with string type (substring)" do
      subject(:rule) { described_class.new(pattern: "example.com", type: "ERR_ABORTED", target: :network) }

      it "matches when type contains the substring" do
        expect(rule.match?("https://example.com/app.js", "net::ERR_ABORTED")).to be true
      end

      it "does not match when type does not contain the substring" do
        expect(rule.match?("https://example.com/app.js", "HTTP 403")).to be false
      end
    end
  end

  describe "#target" do
    it "accepts :network" do
      expect(described_class.new(pattern: //, type: "*", target: :network).target).to eq(:network)
    end

    it "accepts :console" do
      expect(described_class.new(pattern: //, type: "*", target: :console).target).to eq(:console)
    end

    it "accepts :all" do
      expect(described_class.new(pattern: //, type: "*", target: :all).target).to eq(:all)
    end
  end
end
