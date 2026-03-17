# frozen_string_literal: true

require "spec_helper"

RSpec.describe Perchfall::Client do
  include ReportFactory

  # A minimal fake invoker — returns a canned report, records call args.
  let(:recording_invoker) do
    Class.new do
      attr_reader :last_url, :last_opts

      def run(url:, original_url: nil, **opts)
        @last_url  = url
        @last_opts = opts.merge(original_url: original_url)
        Perchfall::Report.new(
          status: "ok", url: original_url || url, duration_ms: 1,
          http_status: 200, network_errors: [], console_errors: [], error: nil
        )
      end
    end.new
  end

  # Each example gets its own limiter so tests are isolated from DEFAULT_LIMITER.
  let(:limiter) { Perchfall::ConcurrencyLimiter.new(limit: 5) }

  subject(:client) { described_class.new(invoker: recording_invoker, limiter: limiter) }

  describe "concurrency limiting" do
    it "raises ConcurrencyLimitError immediately when the limit is 0" do
      tight = Perchfall::ConcurrencyLimiter.new(limit: 0, timeout_ms: 0)
      expect { described_class.new(invoker: recording_invoker, limiter: tight).run(url: "https://example.com") }
        .to raise_error(Perchfall::Errors::ConcurrencyLimitError)
    end

    it "does not invoke Playwright when the limit is exceeded" do
      tight = Perchfall::ConcurrencyLimiter.new(limit: 0, timeout_ms: 0)
      described_class.new(invoker: recording_invoker, limiter: tight).run(url: "https://example.com") rescue nil
      expect(recording_invoker.last_url).to be_nil
    end

    it "releases the slot after a successful run" do
      single = Perchfall::ConcurrencyLimiter.new(limit: 1)
      described_class.new(invoker: recording_invoker, limiter: single).run(url: "https://example.com")
      expect(single.available_slots).to eq(1)
    end
  end

  describe "URL validation" do
    it "rejects file:// URLs before invoking Playwright" do
      expect { client.run(url: "file:///etc/passwd") }
        .to raise_error(ArgumentError, /file/)
      expect(recording_invoker.last_url).to be_nil
    end

    it "rejects URLs with no scheme" do
      expect { client.run(url: "example.com") }
        .to raise_error(ArgumentError)
    end

    it "accepts http and https URLs" do
      expect { client.run(url: "http://example.com") }.not_to raise_error
      expect { client.run(url: "https://example.com") }.not_to raise_error
    end
  end

  it "delegates run to the invoker with the effective (cache-busted) url" do
    client.run(url: "https://example.com")
    expect(recording_invoker.last_url).to match(/\Ahttps:\/\/example\.com\?_perchfall=\d+\z/)
  end

  it "forwards keyword options to the invoker" do
    client.run(url: "https://example.com", timeout_ms: 9_000, scenario_name: "smoke")
    expect(recording_invoker.last_opts).to include(timeout_ms: 9_000, scenario_name: "smoke")
  end

  describe "bust_cache" do
    it "defaults to true" do
      client.run(url: "https://example.com")
      expect(recording_invoker.last_url).to match(/_perchfall=\d+/)
    end

    it "does not forward bust_cache to the invoker — it is consumed by Client" do
      client.run(url: "https://example.com", bust_cache: false)
      expect(recording_invoker.last_opts).not_to have_key(:bust_cache)
    end

    it "validates the cache-busted URL, not the original" do
      # A URL that resolves to an internal address should be caught even after
      # a cache-buster query param is appended. The validator must see the
      # effective URL. We use a fake validator that records what it was given.
      recorded_urls = []
      fake_validator = Class.new do
        define_method(:validate!) { |url| recorded_urls << url }
      end.new

      described_class.new(invoker: recording_invoker, validator: fake_validator, limiter: limiter)
        .run(url: "https://example.com", bust_cache: true)

      expect(recorded_urls.first).to match(/_perchfall=\d+/)
    end

    it "passes the cache-busted URL to the invoker" do
      client.run(url: "https://example.com", bust_cache: true)
      expect(recording_invoker.last_url).to match(/\Ahttps:\/\/example\.com\?_perchfall=\d+\z/)
    end

    it "passes the original URL to the invoker when bust_cache: false" do
      client.run(url: "https://example.com", bust_cache: false)
      expect(recording_invoker.last_url).to eq("https://example.com")
    end

    it "passes the original URL as original_url: so the report reflects the caller's URL" do
      client.run(url: "https://example.com", bust_cache: true)
      expect(recording_invoker.last_opts[:original_url]).to eq("https://example.com")
    end

    it "report.url is the original URL, not the cache-busted URL" do
      report = client.run(url: "https://example.com", bust_cache: true)
      expect(report.url).to eq("https://example.com")
    end
  end

  it "rejects unknown keyword arguments" do
    expect { client.run(url: "https://example.com", timoeut_ms: 5_000) }
      .to raise_error(ArgumentError, /timoeut_ms/)
  end

  describe "wait_until validation" do
    it "accepts the four valid Playwright strategies" do
      %w[load domcontentloaded networkidle commit].each do |value|
        expect { client.run(url: "https://example.com", wait_until: value) }.not_to raise_error
      end
    end

    it "rejects an unknown wait_until value" do
      expect { client.run(url: "https://example.com", wait_until: "notavalidvalue") }
        .to raise_error(ArgumentError, /wait_until/)
    end

    it "rejects wait_until before invoking Playwright" do
      client.run(url: "https://example.com", wait_until: "bogus") rescue nil
      expect(recording_invoker.last_url).to be_nil
    end
  end

  describe "timeout_ms validation" do
    it "accepts a positive integer within the limit" do
      expect { client.run(url: "https://example.com", timeout_ms: 10_000) }.not_to raise_error
    end

    it "accepts the maximum allowed value" do
      expect { client.run(url: "https://example.com", timeout_ms: 60_000) }.not_to raise_error
    end

    it "rejects zero" do
      expect { client.run(url: "https://example.com", timeout_ms: 0) }
        .to raise_error(ArgumentError, /timeout_ms/)
    end

    it "rejects a negative value" do
      expect { client.run(url: "https://example.com", timeout_ms: -1) }
        .to raise_error(ArgumentError, /timeout_ms/)
    end

    it "rejects a non-integer" do
      expect { client.run(url: "https://example.com", timeout_ms: "abc") }
        .to raise_error(ArgumentError, /timeout_ms/)
    end

    it "rejects a value above 60_000" do
      expect { client.run(url: "https://example.com", timeout_ms: 60_001) }
        .to raise_error(ArgumentError, /timeout_ms/)
    end

    it "rejects timeout_ms before invoking Playwright" do
      client.run(url: "https://example.com", timeout_ms: -1) rescue nil
      expect(recording_invoker.last_url).to be_nil
    end
  end

  describe "ignore rules" do
    it "merges caller rules with DEFAULT_IGNORE_RULES and forwards them" do
      extra_rule = Perchfall::IgnoreRule.new(pattern: "shop.app", type: "HTTP 403", target: :network)
      client.run(url: "https://example.com", ignore: [extra_rule])
      forwarded = recording_invoker.last_opts[:ignore]
      expect(forwarded).to include(*Perchfall::DEFAULT_IGNORE_RULES)
      expect(forwarded).to include(extra_rule)
    end

    it "forwards only DEFAULT_IGNORE_RULES when no caller rules given" do
      client.run(url: "https://example.com")
      expect(recording_invoker.last_opts[:ignore]).to eq(Perchfall::DEFAULT_IGNORE_RULES)
    end
  end

  it "returns the report from the invoker" do
    report = client.run(url: "https://example.com")
    expect(report).to be_a(Perchfall::Report)
  end

  it "propagates exceptions from the invoker unchanged" do
    raising_invoker = Class.new do
      def run(url:, **) = raise Perchfall::Errors::InvocationError, "node not found"
    end.new

    expect { described_class.new(invoker: raising_invoker, limiter: limiter).run(url: "https://example.com") }
      .to raise_error(Perchfall::Errors::InvocationError, "node not found")
  end
end
