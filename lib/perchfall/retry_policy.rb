# frozen_string_literal: true

module Perchfall
  # Decides whether a single run's outcome — a Report or a raised exception —
  # is worth retrying, given the conditions the caller opted into.
  #
  # Pure and side-effect free, like ErrorFilter and the parser: it only
  # inspects values and answers a question, so it is fully unit-testable with
  # plain Report objects and exceptions.
  #
  # The caller declares retryable conditions via retry_on:, in one of two forms:
  #
  #   Symbols — a subset of CONDITIONS, e.g. [:load_error, :server_error].
  #     A failure is retryable only when *every* reason it is not-ok is a
  #     declared condition. A 5xx that also carries a console error is NOT
  #     retried when only :server_error is declared — the assertion failure
  #     would never clear, so retrying just burns attempts.
  #
  #   Callable — a proc/lambda taking the outcome (Report or exception) and
  #     returning truthy to retry. The caller owns the entire decision; the
  #     reason model below is bypassed.
  #
  # Console/JS (assertion) errors are deliberately absent from CONDITIONS: they
  # are real defects a retry cannot fix, so they can never be opted into via the
  # symbol form. A report with any console error yields an :assertion reason
  # that no declared symbol can satisfy.
  module RetryPolicy
    # The full set of conditions a caller may name in retry_on:.
    CONDITIONS = %i[
      load_error
      script_error
      server_error
      client_error
      network_error
    ].freeze

    # Applied when retries > 0 and retry_on: is not given. Load, process, and
    # server (5xx) failures are the common transient blips; 4xx and bare
    # net::ERR_* sub-resource failures are available but off by default.
    DEFAULT_CONDITIONS = %i[load_error script_error server_error].freeze

    # @param outcome [Report, Exception] the result of one run attempt
    # @param retry_on [Array<Symbol>, #call] declared conditions or a predicate
    # @return [Boolean] whether the outcome should be retried
    def self.retryable?(outcome, retry_on)
      return !!retry_on.call(outcome) if retry_on.respond_to?(:call)

      reasons = reasons_for(outcome)
      return false if reasons.empty?

      declared = Array(retry_on)
      reasons.all? { |reason| declared.include?(reason) }
    end

    # The set of reasons an outcome is considered a failure. An empty result
    # means "not a failure" (an ok report, or an exception we never retry).
    def self.reasons_for(outcome)
      case outcome
      when Errors::ScriptError then [:script_error]
      when Report              then report_reasons(outcome)
      else                          []
      end
    end

    def self.report_reasons(report)
      return [] if report.ok?

      reasons = []
      reasons << :load_error if report.status == "error"
      report.network_errors.each { |error| reasons << classify_network(error.failure) }
      reasons << :assertion unless report.console_errors.empty?
      reasons.uniq
    end

    def self.classify_network(failure)
      case failure.to_s
      when /\AHTTP 5\d\d\z/ then :server_error
      when /\AHTTP 4\d\d\z/ then :client_error
      else                       :network_error
      end
    end
  end
end
