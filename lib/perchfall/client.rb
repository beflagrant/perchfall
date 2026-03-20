# frozen_string_literal: true

require "uri"

module Perchfall
  # The primary entry point for library consumers.
  #
  # Usage (simple):
  #   client = Perchfall::Client.new
  #   report = client.run(url: "https://example.com")
  #
  # Usage (with options):
  #   report = client.run(
  #     url:           "https://example.com",
  #     timeout_ms:    10_000,
  #     scenario_name: "homepage_smoke"
  #   )
  #
  # Usage (with custom invoker — testing or alternate runtimes):
  #   client = Perchfall::Client.new(invoker: MyCustomInvoker.new)
  #
  # Client is intentionally thin. It owns the public method signature
  # and delegates all real work to the invoker.
  class Client
    VALID_WAIT_UNTIL = %w[load domcontentloaded networkidle commit].freeze

    CACHE_PROFILES = {
      query_bust: { bust_url: true,  headers: {}.freeze }.freeze,
      warm:       { bust_url: false, headers: {}.freeze }.freeze,
      no_cache:   { bust_url: false, headers: { "Cache-Control" => "no-cache" }.freeze }.freeze,
      no_store:   { bust_url: false, headers: { "Cache-Control" => "no-store, no-cache", "Pragma" => "no-cache" }.freeze }.freeze
    }.freeze

    # Headers that could carry credentials, impersonate infrastructure, or
    # manipulate routing. Rejected in custom cache profiles to prevent
    # accidental or malicious injection into all page-load requests.
    FORBIDDEN_HEADERS = %w[
      authorization
      cookie
      set-cookie
      host
      x-forwarded-for
      x-forwarded-host
      x-real-ip
    ].freeze

    def initialize(
      invoker:   PlaywrightInvoker.new,
      validator: UrlValidator.new,
      limiter:   Perchfall.default_limiter
    )
      @invoker   = invoker
      @validator = validator
      @limiter   = limiter
    end

    # Run a synthetic browser check against the given URL.
    # Always returns a Report — callers must check report.ok? to determine success.
    #
    # @param url [String] the URL to check (required, must be http or https)
    # @param timeout_ms [Integer] ms before Playwright gives up (default 30_000)
    # @param scenario_name [String, nil] optional label included in the report
    # @param timestamp [Time] override the run timestamp (default Time.now.utc)
    # @return [Report]
    # @raise [ArgumentError] if the URL is not http/https
    # @raise [Errors::ConcurrencyLimitError] if the concurrency cap is reached
    # @raise [Errors::InvocationError] if Node could not be started
    # @raise [Errors::ScriptError] if the Node script exited non-zero
    # @raise [Errors::ParseError] if the script output was not valid JSON
    def run(url:, **opts)
      invoke(url: url, **opts)
    end

    # Like #run, but raises PageLoadError if the report is not ok.
    # Use this in scripts or jobs that should abort on any page failure.
    #
    # @return [Report] only if report.ok?
    # @raise [Errors::PageLoadError] if the page failed to load or has unignored errors
    def run!(url:, **opts)
      report = invoke(url: url, **opts)
      raise Errors::PageLoadError.new(report) unless report.ok?
      report
    end

    private

    def invoke(url:, ignore: [], wait_until: "load", timeout_ms: 30_000, scenario_name: nil, timestamp: Time.now.utc, cache_profile: :query_bust)
      profile = resolve_cache_profile!(cache_profile)
      validate_wait_until!(wait_until)
      validate_timeout_ms!(timeout_ms)
      effective_url = profile[:bust_url] ? append_cache_buster(url) : url
      @validator.validate!(effective_url)
      merged_ignore = Perchfall::DEFAULT_IGNORE_RULES + ignore
      invoker_opts  = {
        url:           effective_url,
        original_url:  url,
        ignore:        merged_ignore,
        wait_until:    wait_until,
        timeout_ms:    timeout_ms,
        scenario_name: scenario_name,
        timestamp:     timestamp,
        cache_profile: cache_profile
      }
      invoker_opts[:extra_headers] = profile[:headers] unless profile[:headers].empty?
      @limiter.acquire do
        @invoker.run(**invoker_opts)
      end
    end

    private

    def validate_wait_until!(value)
      return if VALID_WAIT_UNTIL.include?(value)

      raise ArgumentError,
            "wait_until must be one of #{VALID_WAIT_UNTIL.join(", ")}. Got: #{value.inspect}"
    end

    def resolve_cache_profile!(profile)
      if profile.is_a?(Symbol)
        CACHE_PROFILES.fetch(profile) do
          raise ArgumentError, "cache_profile must be one of #{CACHE_PROFILES.keys.join(", ")} or a Hash with :headers. Got: #{profile.inspect}"
        end
      else
        headers = profile.fetch(:headers, {})
        validate_custom_headers!(headers)
        { bust_url: false, headers: headers }
      end
    end

    def validate_custom_headers!(headers)
      headers.each_key do |name|
        if FORBIDDEN_HEADERS.include?(name.to_s.downcase)
          raise ArgumentError,
                "cache_profile contains a forbidden header: #{name.inspect}. " \
                "Headers that carry credentials or influence routing (#{FORBIDDEN_HEADERS.join(", ")}) " \
                "may not be set via cache_profile."
        end
      end
    end

    def append_cache_buster(url)
      separator = url.include?("?") ? "&" : "?"
      "#{url}#{separator}_pf=#{Time.now.utc.to_i}"
    end

    MAX_TIMEOUT_MS = 60_000

    def validate_timeout_ms!(value)
      return if value.is_a?(Integer) && value > 0 && value <= MAX_TIMEOUT_MS

      raise ArgumentError,
            "timeout_ms must be a positive integer no greater than #{MAX_TIMEOUT_MS}. Got: #{value.inspect}"
    end
  end
end
