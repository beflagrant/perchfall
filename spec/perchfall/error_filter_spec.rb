# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::ErrorFilter do
  def make_network(url: "https://example.com/app.js", failure: "HTTP 403")
    Perchfall::NetworkError.new(url: url, method: "GET", failure: failure)
  end

  def make_console(text: "Uncaught ReferenceError: foo", type: "error")
    Perchfall::ConsoleError.new(type: type, text: text, location: "https://example.com:10:5")
  end

  let(:network_rule)  { Perchfall::IgnoreRule.new(pattern: "shop.app",      type: "HTTP 403",        target: :network) }
  let(:console_rule)  { Perchfall::IgnoreRule.new(pattern: "ReferenceError", type: "error",           target: :console) }
  let(:aborted_rule)  { Perchfall::IgnoreRule.new(pattern: //,              type: "net::ERR_ABORTED", target: :network) }
  let(:all_rule)      { Perchfall::IgnoreRule.new(pattern: "GTM",           type: "*",               target: :all) }

  subject(:filter) { described_class.new(rules: [network_rule, console_rule, aborted_rule, all_rule]) }

  describe "#filter_network" do
    it "returns :kept and :ignored keys" do
      result = filter.filter_network([])
      expect(result).to have_key(:kept)
      expect(result).to have_key(:ignored)
    end

    it "ignores network errors matched by a :network rule" do
      error  = make_network(url: "https://shop.app/pay", failure: "HTTP 403")
      result = filter.filter_network([error])
      expect(result[:kept]).to be_empty
      expect(result[:ignored]).to eq([error])
    end

    it "ignores network errors matched by an :all rule" do
      error  = make_network(url: "https://cdn.example.com/GTM.js", failure: "HTTP 403")
      result = filter.filter_network([error])
      expect(result[:kept]).to be_empty
      expect(result[:ignored]).to eq([error])
    end

    it "does not apply :console rules to network errors" do
      error  = make_network(url: "https://example.com/ReferenceError.js", failure: "error")
      result = filter.filter_network([error])
      expect(result[:kept]).to eq([error])
      expect(result[:ignored]).to be_empty
    end

    it "keeps errors that match no applicable rule" do
      error  = make_network(url: "https://example.com/app.js", failure: "HTTP 500")
      result = filter.filter_network([error])
      expect(result[:kept]).to eq([error])
      expect(result[:ignored]).to be_empty
    end
  end

  describe "#filter_console" do
    it "returns :kept and :ignored keys" do
      result = filter.filter_console([])
      expect(result).to have_key(:kept)
      expect(result).to have_key(:ignored)
    end

    it "ignores console errors matched by a :console rule" do
      error  = make_console(text: "Uncaught ReferenceError: foo", type: "error")
      result = filter.filter_console([error])
      expect(result[:kept]).to be_empty
      expect(result[:ignored]).to eq([error])
    end

    it "ignores console errors matched by an :all rule" do
      error  = make_console(text: "GTM script failed", type: "error")
      result = filter.filter_console([error])
      expect(result[:kept]).to be_empty
      expect(result[:ignored]).to eq([error])
    end

    it "does not apply :network rules to console errors" do
      error  = make_console(text: "shop.app error", type: "HTTP 403")
      result = filter.filter_console([error])
      expect(result[:kept]).to eq([error])
      expect(result[:ignored]).to be_empty
    end

    it "keeps errors that match no applicable rule" do
      error  = make_console(text: "SyntaxError: unexpected token", type: "error")
      result = filter.filter_console([error])
      expect(result[:kept]).to eq([error])
      expect(result[:ignored]).to be_empty
    end
  end

  describe "with no rules" do
    subject(:filter) { described_class.new(rules: []) }

    it "keeps all network errors" do
      errors = [make_network, make_network(failure: "net::ERR_ABORTED")]
      expect(filter.filter_network(errors)[:kept]).to eq(errors)
    end

    it "keeps all console errors" do
      errors = [make_console, make_console(text: "other")]
      expect(filter.filter_console(errors)[:kept]).to eq(errors)
    end
  end
end
