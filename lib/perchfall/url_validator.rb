# frozen_string_literal: true

require "uri"

module Perchfall
  # Validates that a URL is safe to pass to Playwright.
  #
  # Permitted schemes: http, https only.
  # Rejects file://, ftp://, data:, javascript:, internal addresses, etc.
  #
  # Raises ArgumentError immediately so callers receive a clear, synchronous
  # error before any process is spawned.
  class UrlValidator
    PERMITTED_SCHEMES = %w[http https].freeze

    def validate!(url)
      uri = parse!(url)
      assert_permitted_scheme!(uri, url)
    end

    private

    def parse!(url)
      URI.parse(url)
    rescue URI::InvalidURIError
      raise ArgumentError, "Invalid URL: #{url.inspect}"
    end

    def assert_permitted_scheme!(uri, url)
      return if PERMITTED_SCHEMES.include?(uri.scheme)

      raise ArgumentError,
            "URL scheme #{uri.scheme.inspect} is not permitted. " \
            "Only #{PERMITTED_SCHEMES.join(", ")} URLs are accepted. Got: #{url.inspect}"
    end
  end
end
