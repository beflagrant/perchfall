# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::NetworkErrorFilter do
  def make_error(url: "https://example.com/app.js", failure: "HTTP 403")
    Perchfall::NetworkError.new(url: url, method: "GET", failure: failure)
  end

  let(:shop_rule)     { Perchfall::IgnoreRule.new(url_pattern: "shop.app", failure: "HTTP 403") }
  let(:aborted_rule)  { Perchfall::IgnoreRule.new(url_pattern: //, failure: "net::ERR_ABORTED") }

  describe "#filter" do
    subject(:filter) { described_class.new(rules: [shop_rule, aborted_rule]) }

    it "returns a hash with :kept and :ignored keys" do
      result = filter.filter([])
      expect(result).to have_key(:kept)
      expect(result).to have_key(:ignored)
    end

    it "keeps errors that match no rule" do
      error = make_error(url: "https://example.com/app.js", failure: "HTTP 500")
      result = filter.filter([error])
      expect(result[:kept]).to eq([error])
      expect(result[:ignored]).to be_empty
    end

    it "ignores errors that match a rule" do
      error = make_error(url: "https://shop.app/pay", failure: "HTTP 403")
      result = filter.filter([error])
      expect(result[:kept]).to be_empty
      expect(result[:ignored]).to eq([error])
    end

    it "splits a mixed list correctly" do
      kept_error    = make_error(url: "https://example.com/app.js", failure: "HTTP 500")
      ignored_error = make_error(url: "https://shop.app/pay", failure: "HTTP 403")
      aborted_error = make_error(url: "https://analytics.com/track", failure: "net::ERR_ABORTED")

      result = filter.filter([kept_error, ignored_error, aborted_error])
      expect(result[:kept]).to eq([kept_error])
      expect(result[:ignored]).to contain_exactly(ignored_error, aborted_error)
    end

    it "returns empty arrays when given an empty list" do
      result = filter.filter([])
      expect(result[:kept]).to be_empty
      expect(result[:ignored]).to be_empty
    end
  end

  describe "with no rules" do
    subject(:filter) { described_class.new(rules: []) }

    it "keeps all errors" do
      errors = [make_error, make_error(failure: "net::ERR_ABORTED")]
      result = filter.filter(errors)
      expect(result[:kept]).to eq(errors)
      expect(result[:ignored]).to be_empty
    end
  end
end
