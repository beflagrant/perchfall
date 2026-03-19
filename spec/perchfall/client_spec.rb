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
          http_status: 200, network_errors: [], console_errors: [], error: nil,
          cache_profile: opts[:cache_profile]
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

  it "delegates run to the invoker with the effective (cache-busted) url by default" do
    client.run(url: "https://example.com")
    expect(recording_invoker.last_url).to match(/\Ahttps:\/\/example\.com\?_pf=\d+\z/)
  end

  it "forwards keyword options to the invoker" do
    client.run(url: "https://example.com", timeout_ms: 9_000, scenario_name: "smoke")
    expect(recording_invoker.last_opts).to include(timeout_ms: 9_000, scenario_name: "smoke")
  end

  describe "cache_profile" do
    it "defaults to :query_bust" do
      client.run(url: "https://example.com")
      expect(recording_invoker.last_url).to match(/_pf=\d+/)
    end

    it "uses _pf as the query param name (not _perchfall)" do
      client.run(url: "https://example.com")
      expect(recording_invoker.last_url).not_to match(/_perchfall=/)
      expect(recording_invoker.last_url).to match(/_pf=\d+/)
    end

    it "forwards cache_profile to the invoker so it can be stamped on the report" do
      client.run(url: "https://example.com", cache_profile: :warm)
      expect(recording_invoker.last_opts[:cache_profile]).to eq(:warm)
    end

    it "validates the cache-busted URL, not the original" do
      recorded_urls = []
      fake_validator = Class.new do
        define_method(:validate!) { |url| recorded_urls << url }
      end.new

      described_class.new(invoker: recording_invoker, validator: fake_validator, limiter: limiter)
        .run(url: "https://example.com", cache_profile: :query_bust)

      expect(recorded_urls.first).to match(/_pf=\d+/)
    end

    it ":query_bust appends _pf= to the URL" do
      client.run(url: "https://example.com", cache_profile: :query_bust)
      expect(recording_invoker.last_url).to match(/\Ahttps:\/\/example\.com\?_pf=\d+\z/)
    end

    it ":warm passes the URL unchanged" do
      client.run(url: "https://example.com", cache_profile: :warm)
      expect(recording_invoker.last_url).to eq("https://example.com")
    end

    it ":no_cache passes the URL unchanged and sets Cache-Control header" do
      client.run(url: "https://example.com", cache_profile: :no_cache)
      expect(recording_invoker.last_url).to eq("https://example.com")
      expect(recording_invoker.last_opts[:extra_headers]).to eq("Cache-Control" => "no-cache")
    end

    it ":no_store passes the URL unchanged and sets Cache-Control + Pragma headers" do
      client.run(url: "https://example.com", cache_profile: :no_store)
      expect(recording_invoker.last_url).to eq("https://example.com")
      expect(recording_invoker.last_opts[:extra_headers]).to eq(
        "Cache-Control" => "no-store, no-cache",
        "Pragma"        => "no-cache"
      )
    end

    it ":query_bust does not forward extra_headers" do
      client.run(url: "https://example.com", cache_profile: :query_bust)
      expect(recording_invoker.last_opts).not_to have_key(:extra_headers)
    end

    it ":warm does not forward extra_headers" do
      client.run(url: "https://example.com", cache_profile: :warm)
      expect(recording_invoker.last_opts).not_to have_key(:extra_headers)
    end

    it "accepts a custom hash with headers:" do
      client.run(url: "https://example.com", cache_profile: { headers: { "Cache-Control" => "max-age=0" } })
      expect(recording_invoker.last_url).to eq("https://example.com")
      expect(recording_invoker.last_opts[:extra_headers]).to eq("Cache-Control" => "max-age=0")
    end

    describe "custom header validation" do
      %w[
        Authorization
        Cookie
        Set-Cookie
        Host
        X-Forwarded-For
        X-Forwarded-Host
        X-Real-IP
      ].each do |forbidden|
        it "rejects #{forbidden} header in custom profile" do
          expect {
            client.run(url: "https://example.com", cache_profile: { headers: { forbidden => "value" } })
          }.to raise_error(ArgumentError, /#{Regexp.escape(forbidden)}/)
        end

        it "rejects #{forbidden} header case-insensitively" do
          expect {
            client.run(url: "https://example.com", cache_profile: { headers: { forbidden.downcase => "value" } })
          }.to raise_error(ArgumentError, /#{Regexp.escape(forbidden.downcase)}/i)
        end
      end

      it "accepts safe cache-related headers" do
        expect {
          client.run(url: "https://example.com", cache_profile: { headers: {
            "Cache-Control" => "no-cache",
            "Pragma"        => "no-cache",
            "Accept"        => "text/html"
          } })
        }.not_to raise_error
      end
    end

    it "rejects an unknown symbol" do
      expect { client.run(url: "https://example.com", cache_profile: :turbo_flush) }
        .to raise_error(ArgumentError, /cache_profile/)
    end

    it "passes the original URL as original_url: so the report reflects the caller's URL" do
      client.run(url: "https://example.com", cache_profile: :query_bust)
      expect(recording_invoker.last_opts[:original_url]).to eq("https://example.com")
    end

    it "report.url is the original URL, not the cache-busted URL" do
      report = client.run(url: "https://example.com", cache_profile: :query_bust)
      expect(report.url).to eq("https://example.com")
    end

    it "includes cache_profile in the report" do
      report = client.run(url: "https://example.com", cache_profile: :no_cache)
      expect(report.cache_profile).to eq(:no_cache)
    end

    it "includes cache_profile in report.to_h" do
      report = client.run(url: "https://example.com", cache_profile: :warm)
      expect(report.to_h[:cache_profile]).to eq(:warm)
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

    it "rejects wait_until before building the effective URL" do
      validated_urls = []
      fake_validator = Class.new do
        define_method(:validate!) { |url| validated_urls << url }
      end.new

      described_class.new(invoker: recording_invoker, validator: fake_validator, limiter: limiter)
        .run(url: "https://example.com", wait_until: "bogus") rescue nil

      expect(validated_urls).to be_empty
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

    it "rejects timeout_ms before building the effective URL" do
      validated_urls = []
      fake_validator = Class.new do
        define_method(:validate!) { |url| validated_urls << url }
      end.new

      described_class.new(invoker: recording_invoker, validator: fake_validator, limiter: limiter)
        .run(url: "https://example.com", timeout_ms: -1) rescue nil

      expect(validated_urls).to be_empty
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
