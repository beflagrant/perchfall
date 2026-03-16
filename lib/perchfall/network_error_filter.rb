# frozen_string_literal: true

module Perchfall
  # Splits a list of NetworkError objects into kept and ignored groups
  # based on a list of IgnoreRule objects.
  #
  # An error is ignored if any rule matches it; otherwise it is kept.
  class NetworkErrorFilter
    def initialize(rules:)
      @rules = rules
    end

    # @param errors [Array<NetworkError>]
    # @return [Hash{Symbol => Array<NetworkError>}] with keys :kept and :ignored
    def filter(errors)
      kept, ignored = errors.partition { |e| @rules.none? { |r| r.match?(e) } }
      { kept: kept, ignored: ignored }
    end
  end
end
