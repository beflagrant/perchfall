# frozen_string_literal: true

require_relative "perchfall/version"
require_relative "perchfall/errors"
require_relative "perchfall/network_error"
require_relative "perchfall/console_error"
require_relative "perchfall/report"
require_relative "perchfall/ignore_rule"
require_relative "perchfall/network_error_filter"
require_relative "perchfall/command_runner"
require_relative "perchfall/concurrency_limiter"
require_relative "perchfall/url_validator"
require_relative "perchfall/parsers/playwright_json_parser"
require_relative "perchfall/playwright_invoker"
require_relative "perchfall/client"

# Perchfall — synthetic browser monitoring via Playwright.
#
# Quick start:
#   report = Perchfall.run(url: "https://example.com")
#   report.ok?          # => true
#   report.http_status  # => 200
#   report.to_json      # => '{"status":"ok",...}'
#
# For advanced use, inject collaborators:
#   client = Perchfall::Client.new(invoker: MyInvoker.new)
#   report = client.run(url: "https://example.com", scenario_name: "homepage_smoke")
module Perchfall
  # Network errors suppressed by default on every run.
  # ERR_ABORTED is a browser-side abort (analytics beacons, cancelled prefetches)
  # and is never a signal of real page failure.
  # Callers extend this list by passing ignore: to Perchfall.run or Client#run.
  DEFAULT_IGNORE_RULES = [
    IgnoreRule.new(url_pattern: //, failure: "net::ERR_ABORTED"),
  ].freeze

  # Process-wide concurrency limiter. Caps simultaneous Chromium instances
  # across all threads. Override by passing limiter: to Client.new.
  #
  # Lazily initialised so requiring the gem does not create threads or
  # mutexes until the first actual run.
  def self.default_limiter
    @default_limiter ||= ConcurrencyLimiter.new(limit: 5)
  end

  # Convenience method. Equivalent to Perchfall::Client.new.run(url:, **opts).
  # Creates a fresh Client (and thus a fresh PlaywrightInvoker) on each call —
  # no shared state between invocations.
  #
  # @param url [String]
  # @param opts [Hash] forwarded to Client#run
  # @return [Report]
  def self.run(url:, **opts)
    Client.new.run(url: url, **opts)
  end
end
