# frozen_string_literal: true

module Perchfall
  # Immutable value object representing a browser console error message
  # captured during a Playwright browser run.
  ConsoleError = Data.define(:type, :text, :location) do
    def to_h
      { type: type, text: text, location: location }
    end

    def to_json(...)
      to_h.to_json(...)
    end
  end
end
