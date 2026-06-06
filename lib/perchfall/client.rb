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
      query_bust: { bust_url: true, headers: {}.freeze }.freeze,
      warm: { bust_url: false, headers: {}.freeze }.freeze,
      no_cache: { bust_url: false, headers: { "Cache-Control" => "no-cache" }.freeze }.freeze,
      no_store: { bust_url: false,
                  headers: { "Cache-Control" => "no-store, no-cache", "Pragma" => "no-cache" }.freeze }.freeze
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
      limiter:   Perchfall.default_limiter,
      sleeper:   ->(seconds) { sleep(seconds) }
    )
      @invoker   = invoker
      @validator = validator
      @limiter   = limiter
      @sleeper   = sleeper
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
    def run(url:, **)
      invoke(url: url, **)
    end

    # Like #run, but raises PageLoadError if the report is not ok.
    # Use this in scripts or jobs that should abort on any page failure.
    #
    # @return [Report] only if report.ok?
    # @raise [Errors::PageLoadError] if the page failed to load or has unignored errors
    def run!(url:, **)
      report = invoke(url: url, **)
      raise Errors::PageLoadError.new(report) unless report.ok?

      report
    end

    DEFAULT_RESOURCE_THRESHOLD = Parsers::PlaywrightJsonParser::DEFAULT_LARGE_RESOURCE_THRESHOLD_BYTES

    RunOptions = Data.define(
      :url, :ignore, :wait_until, :timeout_ms, :scenario_name,
      :timestamp, :cache_profile, :capture_resources, :large_resource_threshold_bytes,
      :retries, :retry_on, :retry_backoff_ms
    ) do
      def self.from_kwargs(url:, ignore: [], wait_until: "load", timeout_ms: 30_000,
                           scenario_name: nil, timestamp: Time.now.utc,
                           cache_profile: :query_bust, capture_resources: false,
                           large_resource_threshold_bytes: DEFAULT_RESOURCE_THRESHOLD,
                           retries: 0, retry_on: RetryPolicy::DEFAULT_CONDITIONS,
                           retry_backoff_ms: 250)
        new(url: url, ignore: ignore, wait_until: wait_until, timeout_ms: timeout_ms,
            scenario_name: scenario_name, timestamp: timestamp, cache_profile: cache_profile,
            capture_resources: capture_resources,
            large_resource_threshold_bytes: large_resource_threshold_bytes,
            retries: retries, retry_on: retry_on, retry_backoff_ms: retry_backoff_ms)
      end
    end

    private

    def invoke(url:, **)
      opts    = RunOptions.from_kwargs(url: url, **)
      profile = resolve_cache_profile!(opts.cache_profile)
      validate_wait_until!(opts.wait_until)
      validate_timeout_ms!(opts.timeout_ms)
      validate_retries!(opts.retries)
      validate_retry_backoff_ms!(opts.retry_backoff_ms)
      validate_retry_on!(opts.retry_on)
      run_with_retries(opts, profile)
    end

    # Runs up to retries+1 attempts, stopping early as soon as an attempt
    # succeeds or produces an outcome the caller did not opt to retry. The
    # backoff sleep happens outside @limiter.acquire so no browser slot is held
    # while waiting.
    #
    # A retryable ScriptError is captured as the attempt's *outcome* so the
    # report path and the exception path share one decision: on the final
    # attempt, or when retry_on does not cover the outcome, finish — re-raising
    # if the outcome was an exception, otherwise returning the report.
    def run_with_retries(opts, profile)
      attempt = 0
      loop do
        attempt += 1
        outcome = attempt_run(opts, profile)

        if attempt > opts.retries || !RetryPolicy.retryable?(outcome, opts.retry_on)
          raise outcome if outcome.is_a?(Exception)

          return outcome
        end

        backoff(opts.retry_backoff_ms, attempt)
      end
    end

    # One attempt. A ScriptError is returned as a value so it can flow through
    # the same retry decision as a not-ok report; every other exception
    # propagates immediately and is never retried.
    def attempt_run(opts, profile)
      run_once(opts, profile)
    rescue Errors::ScriptError => e
      e
    end

    def run_once(opts, profile)
      effective_url = profile[:bust_url] ? append_cache_buster(opts.url) : opts.url
      @validator.validate!(effective_url)
      @limiter.acquire { @invoker.run(**build_invoker_opts(opts, effective_url, profile)) }
    end

    # Exponential: the wait before the 1st retry is base_ms, doubling each
    # attempt, clamped so no single wait exceeds MAX_RETRY_BACKOFF_MS — a high
    # base combined with many retries must not balloon into a multi-hour sleep.
    def backoff(base_ms, attempt)
      return if base_ms.zero?

      delay_ms = [base_ms * (2**(attempt - 1)), MAX_RETRY_BACKOFF_MS].min
      @sleeper.call(delay_ms / 1000.0)
    end

    def build_invoker_opts(opts, effective_url, profile)
      result = {
        url: effective_url, original_url: opts.url,
        ignore: Perchfall::DEFAULT_IGNORE_RULES + opts.ignore,
        wait_until: opts.wait_until, timeout_ms: opts.timeout_ms,
        scenario_name: opts.scenario_name, timestamp: opts.timestamp,
        cache_profile: opts.cache_profile
      }
      result[:extra_headers] = profile[:headers] unless profile[:headers].empty?
      if opts.capture_resources
        result[:capture_resources]              = true
        result[:large_resource_threshold_bytes] = opts.large_resource_threshold_bytes
      end
      result
    end

    def validate_wait_until!(value)
      return if VALID_WAIT_UNTIL.include?(value)

      raise ArgumentError,
            "wait_until must be one of #{VALID_WAIT_UNTIL.join(", ")}. Got: #{value.inspect}"
    end

    def resolve_cache_profile!(profile)
      if profile.is_a?(Symbol)
        CACHE_PROFILES.fetch(profile) do
          raise ArgumentError,
                "cache_profile must be one of #{CACHE_PROFILES.keys.join(", ")} or a Hash with :headers. Got: #{profile.inspect}"
        end
      else
        headers = profile.fetch(:headers, {})
        validate_custom_headers!(headers)
        { bust_url: false, headers: headers }
      end
    end

    def validate_custom_headers!(headers)
      headers.each_key do |name|
        next unless FORBIDDEN_HEADERS.include?(name.to_s.downcase)

        raise ArgumentError,
              "cache_profile contains a forbidden header: #{name.inspect}. " \
              "Headers that carry credentials or influence routing (#{FORBIDDEN_HEADERS.join(", ")}) " \
              "may not be set via cache_profile."
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

    MAX_RETRIES = 10

    def validate_retries!(value)
      return if value.is_a?(Integer) && value >= 0 && value <= MAX_RETRIES

      raise ArgumentError,
            "retries must be an integer between 0 and #{MAX_RETRIES}. Got: #{value.inspect}"
    end

    MAX_RETRY_BACKOFF_MS = 30_000

    def validate_retry_backoff_ms!(value)
      return if value.is_a?(Integer) && value >= 0 && value <= MAX_RETRY_BACKOFF_MS

      raise ArgumentError,
            "retry_backoff_ms must be an integer between 0 and #{MAX_RETRY_BACKOFF_MS}. Got: #{value.inspect}"
    end

    def validate_retry_on!(value)
      return if value.respond_to?(:call)

      # A bare condition symbol is accepted too — RetryPolicy.retryable? wraps
      # retry_on in Array(...), so [:server_error] and :server_error behave
      # identically; validation must not reject the form the policy honours.
      conditions = value.is_a?(Array) ? value : [value]
      return if conditions.all? { |condition| RetryPolicy::CONDITIONS.include?(condition) }

      raise ArgumentError,
            "retry_on must be a callable, a condition symbol, or an array of " \
            "#{RetryPolicy::CONDITIONS.join(", ")}. Got: #{value.inspect}"
    end
  end
end
