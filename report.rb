# frozen_string_literal: true

require './lib/perchfall'

report = Perchfall.run(url: 'https://example.com')

if report.ok?
  puts "#{report.url} loaded in #{report.duration_ms}ms"
  puts '*' * 40
  puts report.to_json
else
  puts "Page failed: #{report.network_errors.map(&:failure).join(', ')}"
end
