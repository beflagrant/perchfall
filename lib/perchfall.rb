# frozen_string_literal: true

require_relative "perchfall/version"
require_relative "perchfall/errors"
require_relative "perchfall/network_error"
require_relative "perchfall/console_error"
require_relative "perchfall/report"
require_relative "perchfall/ignore_rule"
require_relative "perchfall/error_filter"
require_relative "perchfall/command_runner"
require_relative "perchfall/concurrency_limiter"
require_relative "perchfall/url_validator"
require_relative "perchfall/resource"
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
  # Errors suppressed by default on every run.
  # ERR_ABORTED is a browser-side abort (analytics beacons, cancelled prefetches)
  # and is never a signal of real page failure.
  # Callers extend this list by passing ignore: to Perchfall.run or Client#run.
  DEFAULT_IGNORE_RULES = [
    IgnoreRule.new(pattern: //, type: "net::ERR_ABORTED", target: :network),
  ].freeze

  # Process-wide concurrency limiter. Caps simultaneous Chromium instances
  # across all threads. Override by passing limiter: to Client.new.
  #
  # Lazily initialised so requiring the gem does not create threads or
  # mutexes until the first actual run.
  def self.default_limiter
    @default_limiter ||= ConcurrencyLimiter.new(limit: 5)
  end

  # Returns a Report always — callers check report.ok? to determine success.
  # Use this when you want to handle or notify on failures yourself.
  #
  # @param url [String]
  # @param opts [Hash] forwarded to Client#run
  # @return [Report]
  def self.run(url:, **opts)
    Client.new.run(url: url, **opts)
  end

  # Like .run, but raises PageLoadError if the report is not ok.
  # Use this in scripts or jobs that should abort on any page failure.
  #
  # @param url [String]
  # @param opts [Hash] forwarded to Client#run!
  # @return [Report] only if report.ok?
  # @raise [Errors::PageLoadError]
  def self.run!(url:, **opts)
    Client.new.run!(url: url, **opts)
  end
end
