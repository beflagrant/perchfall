# frozen_string_literal: true

module Perchfall
  # Immutable value object representing a single failed network request
  # captured during a Playwright browser run.
  NetworkError = Data.define(:url, :method, :failure) do
    def to_h
      { url: url, method: method, failure: failure }
    end

    def to_json(...)
      to_h.to_json(...)
    end
  end
end
