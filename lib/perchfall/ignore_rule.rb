# frozen_string_literal: true

module Perchfall
  # Describes a single error suppression rule applicable to NetworkError,
  # ConsoleError, or both.
  #
  # pattern - String (substring match) or Regexp matched against the primary field:
  #           NetworkError#url or ConsoleError#text.
  # type    - String (substring match), Regexp, or "*" (wildcard) matched against
  #           the secondary field: NetworkError#failure or ConsoleError#type.
  # target  - Symbol: :network, :console, or :all — which error type this rule applies to.
  #
  # A rule matches when both pattern and type match their respective values.
  # The filter is responsible for routing rules to the correct error type via target.
  IgnoreRule = Data.define(:pattern, :type, :target) do
    # @param primary   [String] the primary field value (url or text)
    # @param secondary [String] the secondary field value (failure or type)
    def match?(primary, secondary)
      pattern_matches?(primary) && type_matches?(secondary)
    end

    private

    def pattern_matches?(value)
      case pattern
      when Regexp then pattern.match?(value)
      else             value.include?(pattern)
      end
    end

    def type_matches?(value)
      case type
      when "*"    then true
      when Regexp then type.match?(value)
      else             value.include?(type)
      end
    end
  end
end
