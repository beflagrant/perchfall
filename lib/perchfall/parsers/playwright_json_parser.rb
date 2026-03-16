# frozen_string_literal: true

require "json"

module Perchfall
  module Parsers
    # Parses the raw JSON string produced by playwright/check.js into a Report.
    #
    # This is the only place where raw data becomes domain objects.
    # No side effects — pure data transformation, fully unit-testable with strings.
    class PlaywrightJsonParser
      def initialize(filter: NetworkErrorFilter.new(rules: []))
        @filter = filter
      end

      def parse(raw_json, scenario_name: nil, timestamp: Time.now.utc)
        data = JSON.parse(raw_json, symbolize_names: true)
        build_report(data, scenario_name: scenario_name, timestamp: timestamp)
      rescue JSON::ParserError => e
        raise Errors::ParseError, "Invalid JSON from Playwright script: #{e.message}"
      end

      private

      def build_report(data, scenario_name:, timestamp:)
        all_network_errors = parse_network_errors(data.fetch(:network_errors, []))
        filtered           = @filter.filter(all_network_errors)

        Report.new(
          status:                 data.fetch(:status),
          url:                    data.fetch(:url),
          duration_ms:            data.fetch(:duration_ms),
          http_status:            data[:http_status],
          network_errors:         filtered[:kept],
          ignored_network_errors: filtered[:ignored],
          console_errors:         parse_console_errors(data.fetch(:console_errors, [])),
          error:                  data[:error],
          scenario_name:          scenario_name,
          timestamp:              timestamp
        )
      rescue KeyError => e
        raise Errors::ParseError, "Playwright JSON missing required field: #{e.message}"
      end

      def parse_network_errors(raw)
        raw.map do |item|
          NetworkError.new(
            url:     item.fetch(:url),
            method:  item.fetch(:method),
            failure: item.fetch(:failure)
          )
        end
      rescue KeyError => e
        raise Errors::ParseError, "Malformed network_error entry: #{e.message}"
      end

      def parse_console_errors(raw)
        raw.map do |item|
          ConsoleError.new(
            type:     item.fetch(:type),
            text:     item.fetch(:text),
            location: item.fetch(:location)
          )
        end
      rescue KeyError => e
        raise Errors::ParseError, "Malformed console_error entry: #{e.message}"
      end
    end
  end
end
