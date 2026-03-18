# frozen_string_literal: true

require "json"

module Perchfall
  # Immutable value object representing the full result of one synthetic check.
  #
  # Attributes:
  #   status                 - String: "ok" or "error"
  #   url                    - String: the checked URL
  #   scenario_name          - String or nil: optional label for the check
  #   timestamp              - Time: when the run was initiated
  #   duration_ms            - Integer: wall-clock time of the browser run
  #   http_status            - Integer or nil: HTTP response code, nil if page never loaded
  #   network_errors         - Array<NetworkError>: failures not matched by any ignore rule
  #   ignored_network_errors - Array<NetworkError>: failures suppressed by ignore rules
  #   console_errors         - Array<ConsoleError>: errors not matched by any ignore rule
  #   ignored_console_errors - Array<ConsoleError>: errors suppressed by ignore rules
  #   error                  - String or nil: set only when status == "error"
  #   screenshots            - String or nil: base64-encoded PNG, present when screenshots were captured
  class Report
    attr_reader :status, :url, :scenario_name, :timestamp, :duration_ms,
                :http_status, :network_errors, :ignored_network_errors,
                :console_errors, :ignored_console_errors, :error, :screenshots

    def initialize(
      status:,
      url:,
      duration_ms:,
      http_status:,
      network_errors:,
      console_errors:,
      error:,
      ignored_network_errors: [],
      ignored_console_errors: [],
      scenario_name: nil,
      timestamp: Time.now.utc,
      screenshots: nil
    )
      @status                 = status.freeze
      @url                    = url.freeze
      @scenario_name          = scenario_name&.freeze
      @timestamp              = timestamp
      @duration_ms            = duration_ms
      @http_status            = http_status
      @network_errors         = network_errors.freeze
      @ignored_network_errors = ignored_network_errors.freeze
      @console_errors         = console_errors.freeze
      @ignored_console_errors = ignored_console_errors.freeze
      @error                  = error&.freeze
      @screenshots            = screenshots&.freeze
      freeze
    end

    def ok?
      status == "ok"
    end

    # Returns a hash representation of the report suitable for logging,
    # storage, and transmission. Screenshot data is excluded by default
    # because it can contain sensitive page content (session state, PII,
    # internal tooling). Pass include_screenshots: true only when you have
    # explicitly decided it is safe to include in the output destination.
    def to_h(include_screenshots: false)
      h = {
        status:         status,
        url:            url,
        scenario_name:  scenario_name,
        timestamp:      timestamp.iso8601,
        ok:             ok?,
        http_status:    http_status,
        duration_ms:    duration_ms,
        network_errors:         network_errors.map(&:to_h),
        ignored_network_errors: ignored_network_errors.map(&:to_h),
        console_errors:         console_errors.map(&:to_h),
        ignored_console_errors: ignored_console_errors.map(&:to_h),
        error:          error
      }
      h[:screenshots] = screenshots if include_screenshots
      h
    end

    def to_json(*args, include_screenshots: false, **opts)
      to_h(include_screenshots: include_screenshots).to_json(*args, **opts)
    end

    def ==(other)
      other.is_a?(Report) &&
        to_h == other.to_h &&
        screenshots == other.screenshots
    end
  end
end
