# frozen_string_literal: true

require "json"

module Perchfall
  # Immutable value object representing the full result of one synthetic check.
  #
  # Attributes:
  #   status         - String: "ok" or "error"
  #   url            - String: the checked URL
  #   scenario_name  - String or nil: optional label for the check
  #   timestamp      - Time: when the run was initiated
  #   duration_ms    - Integer: wall-clock time of the browser run
  #   http_status    - Integer or nil: HTTP response code, nil if page never loaded
  #   network_errors - Array<NetworkError>
  #   console_errors - Array<ConsoleError>
  #   error          - String or nil: set only when status == "error"
  class Report
    attr_reader :status, :url, :scenario_name, :timestamp, :duration_ms,
                :http_status, :network_errors, :console_errors, :error

    def initialize(
      status:,
      url:,
      duration_ms:,
      http_status:,
      network_errors:,
      console_errors:,
      error:,
      scenario_name: nil,
      timestamp: Time.now.utc
    )
      @status         = status.freeze
      @url            = url.freeze
      @scenario_name  = scenario_name&.freeze
      @timestamp      = timestamp
      @duration_ms    = duration_ms
      @http_status    = http_status
      @network_errors = network_errors.freeze
      @console_errors = console_errors.freeze
      @error          = error&.freeze
      freeze
    end

    def ok?
      status == "ok"
    end

    def to_h
      {
        status:         status,
        url:            url,
        scenario_name:  scenario_name,
        timestamp:      timestamp.iso8601,
        ok:             ok?,
        http_status:    http_status,
        duration_ms:    duration_ms,
        network_errors: network_errors.map(&:to_h),
        console_errors: console_errors.map(&:to_h),
        error:          error
      }
    end

    def to_json(...)
      to_h.to_json(...)
    end

    def ==(other)
      other.is_a?(Report) && to_h == other.to_h
    end
  end
end
