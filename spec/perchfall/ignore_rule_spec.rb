# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::IgnoreRule do
  def make_error(url: "https://example.com/app.js", failure: "HTTP 403")
    Perchfall::NetworkError.new(url: url, method: "GET", failure: failure)
  end

  describe "#match?" do
    context "with string url_pattern (substring)" do
      subject(:rule) { described_class.new(url_pattern: "shop.app/pay", failure: "HTTP 403") }

      it "matches when url contains the pattern and failure matches" do
        error = make_error(url: "https://shop.app/pay?foo=bar", failure: "HTTP 403")
        expect(rule.match?(error)).to be true
      end

      it "does not match when url does not contain the pattern" do
        error = make_error(url: "https://other.com/pay", failure: "HTTP 403")
        expect(rule.match?(error)).to be false
      end

      it "does not match when failure differs" do
        error = make_error(url: "https://shop.app/pay", failure: "HTTP 500")
        expect(rule.match?(error)).to be false
      end
    end

    context "with regex url_pattern" do
      subject(:rule) { described_class.new(url_pattern: /google-analytics\.com/, failure: "net::ERR_ABORTED") }

      it "matches when url matches the regex and failure matches" do
        error = make_error(url: "https://www.google-analytics.com/g/collect", failure: "net::ERR_ABORTED")
        expect(rule.match?(error)).to be true
      end

      it "does not match when url does not match the regex" do
        error = make_error(url: "https://example.com/track", failure: "net::ERR_ABORTED")
        expect(rule.match?(error)).to be false
      end
    end

    context "with wildcard failure ('*')" do
      subject(:rule) { described_class.new(url_pattern: "shop.app", failure: "*") }

      it "matches any failure for matching url" do
        expect(rule.match?(make_error(url: "https://shop.app/pay", failure: "HTTP 403"))).to be true
        expect(rule.match?(make_error(url: "https://shop.app/pay", failure: "HTTP 500"))).to be true
        expect(rule.match?(make_error(url: "https://shop.app/pay", failure: "net::ERR_ABORTED"))).to be true
      end

      it "does not match when url does not match" do
        expect(rule.match?(make_error(url: "https://other.com/pay", failure: "HTTP 403"))).to be false
      end
    end

    context "with regex failure" do
      subject(:rule) { described_class.new(url_pattern: "example.com", failure: /HTTP \d{3}/) }

      it "matches when failure matches the regex" do
        expect(rule.match?(make_error(failure: "HTTP 403"))).to be true
        expect(rule.match?(make_error(failure: "HTTP 500"))).to be true
      end

      it "does not match when failure does not match the regex" do
        expect(rule.match?(make_error(failure: "net::ERR_ABORTED"))).to be false
      end
    end

    context "with string failure (substring)" do
      subject(:rule) { described_class.new(url_pattern: "example.com", failure: "ERR_ABORTED") }

      it "matches when failure contains the substring" do
        expect(rule.match?(make_error(failure: "net::ERR_ABORTED"))).to be true
      end

      it "does not match when failure does not contain the substring" do
        expect(rule.match?(make_error(failure: "HTTP 403"))).to be false
      end
    end
  end
end
