# frozen_string_literal: true

# Builds Perchfall::Report instances with sensible defaults.
# Keeps individual specs focused on the attribute under test.
module ReportFactory
  def build_report(overrides = {})
    defaults = {
      status:         "ok",
      url:            "https://example.com",
      duration_ms:    100,
      http_status:    200,
      network_errors:         [],
      ignored_network_errors: [],
      console_errors:         [],
      ignored_console_errors: [],
      error:          nil,
      resources:      []
    }
    Perchfall::Report.new(**defaults.merge(overrides))
  end
end
