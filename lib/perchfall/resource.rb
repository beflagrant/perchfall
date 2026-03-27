# frozen_string_literal: true

module Perchfall
  # Represents a single resource loaded during a page run.
  #
  # Attributes:
  #   url           - String: the resource URL
  #   http_method   - String: HTTP method (e.g. "GET")
  #   status        - Integer: HTTP response status code
  #   content_type  - String or nil: Content-Type header value
  #   transfer_size - Integer or nil: wire bytes from Content-Length header;
  #                   nil means the header was absent (chunked/inline) — unknown, not zero
  #   resource_type - String: Playwright resource type (e.g. "image", "script", "stylesheet")
  Resource = Data.define(:url, :http_method, :status, :content_type, :transfer_size, :resource_type)
end
