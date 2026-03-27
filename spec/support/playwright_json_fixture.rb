# frozen_string_literal: true

# Helpers for building Playwright JSON output strings in specs.
# Include this module in example groups that need JSON fixtures.
module PlaywrightJsonFixture
  def ok_json(overrides = {})
    base = {
      status:         "ok",
      url:            "https://example.com",
      duration_ms:    512,
      http_status:    200,
      network_errors: [],
      console_errors: [],
      error:          nil
    }
    base.merge(overrides).to_json
  end

  def error_json(overrides = {})
    base = {
      status:         "error",
      url:            "https://example.com",
      duration_ms:    312,
      http_status:    nil,
      network_errors: [],
      console_errors: [],
      error:          "net::ERR_NAME_NOT_RESOLVED"
    }
    base.merge(overrides).to_json
  end

  def network_error_entry(overrides = {})
    { url: "https://example.com/app.js", method: "GET", failure: "net::ERR_ABORTED" }
      .merge(overrides)
  end

  def console_error_entry(overrides = {})
    { type: "error", text: "Uncaught ReferenceError: foo is not defined", location: "https://example.com/app.js:10:5" }
      .merge(overrides)
  end

  def resource_entry(overrides = {})
    {
      url:           "https://example.com/hero.jpg",
      method:        "GET",
      status:        200,
      content_type:  "image/jpeg",
      transfer_size: 204_800,
      resource_type: "image"
    }.merge(overrides)
  end
end
