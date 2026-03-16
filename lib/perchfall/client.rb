# frozen_string_literal: true

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
    #
    # @param url [String] the URL to check (required, must be http or https)
    # @param timeout_ms [Integer] ms before Playwright gives up (default 30_000)
    # @param scenario_name [String, nil] optional label included in the report
    # @param timestamp [Time] override the run timestamp (default Time.now.utc)
    # @return [Report] on success
    # @raise [ArgumentError] if the URL is not http/https
    # @raise [Errors::ConcurrencyLimitError] if the concurrency cap is reached
    # @raise [Errors::InvocationError] if Node could not be started
    # @raise [Errors::ScriptError] if the Node script exited non-zero
    # @raise [Errors::ParseError] if the script output was not valid JSON
    # @raise [Errors::PageLoadError] if the page itself failed to load
    VALID_WAIT_UNTIL = %w[load domcontentloaded networkidle commit].freeze

    def run(url:, ignore: [], wait_until: "load", timeout_ms: 30_000, **opts)
      @validator.validate!(url)
      validate_wait_until!(wait_until)
      validate_timeout_ms!(timeout_ms)
      merged_ignore = Perchfall::DEFAULT_IGNORE_RULES + ignore
      @limiter.acquire { @invoker.run(url: url, ignore: merged_ignore, wait_until: wait_until, timeout_ms: timeout_ms, **opts) }
    end

    private

    def validate_wait_until!(value)
      return if VALID_WAIT_UNTIL.include?(value)

      raise ArgumentError,
            "wait_until must be one of #{VALID_WAIT_UNTIL.join(", ")}. Got: #{value.inspect}"
    end

    def validate_timeout_ms!(value)
      return if value.is_a?(Integer) && value > 0

      raise ArgumentError,
            "timeout_ms must be a positive integer. Got: #{value.inspect}"
    end
  end
end
