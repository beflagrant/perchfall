# frozen_string_literal: true

module Perchfall
  # Applies a unified list of IgnoreRule objects to both NetworkError and ConsoleError arrays.
  #
  # Rules are routed by target:
  #   :network — applied only to NetworkError (matched on url + failure)
  #   :console — applied only to ConsoleError (matched on text + type)
  #   :all     — applied to both error types
  class ErrorFilter
    def initialize(rules:)
      @network_rules = rules.select { |r| r.target == :network || r.target == :all }
      @console_rules = rules.select { |r| r.target == :console || r.target == :all }
    end

    # @param errors [Array<NetworkError>]
    # @return [Hash{Symbol => Array<NetworkError>}] with keys :kept and :ignored
    def filter_network(errors)
      partition(errors) { |e| @network_rules.any? { |r| r.match?(e.url, e.failure) } }
    end

    # @param errors [Array<ConsoleError>]
    # @return [Hash{Symbol => Array<ConsoleError>}] with keys :kept and :ignored
    def filter_console(errors)
      partition(errors) { |e| @console_rules.any? { |r| r.match?(e.text, e.type) } }
    end

    private

    def partition(errors, &should_ignore)
      kept, ignored = errors.partition { |e| !should_ignore.call(e) }
      { kept: kept, ignored: ignored }
    end
  end
end
