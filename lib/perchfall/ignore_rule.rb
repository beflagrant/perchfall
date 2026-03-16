# frozen_string_literal: true

module Perchfall
  # Describes a single network-error suppression rule.
  #
  # url_pattern - String (substring match) or Regexp matched against NetworkError#url.
  # failure     - String (substring match), Regexp, or "*" (wildcard) matched against NetworkError#failure.
  #
  # A rule matches a NetworkError when both url_pattern and failure match.
  IgnoreRule = Data.define(:url_pattern, :failure) do
    def match?(network_error)
      url_matches?(network_error.url) && failure_matches?(network_error.failure)
    end

    private

    def url_matches?(url)
      case url_pattern
      when Regexp then url_pattern.match?(url)
      else             url.include?(url_pattern)
      end
    end

    def failure_matches?(error_failure)
      case failure
      when "*"    then true
      when Regexp then failure.match?(error_failure)
      else             error_failure.include?(failure)
      end
    end
  end
end
