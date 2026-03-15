require 'perchfall'

report = Perchfall.run(url: 'https://www.beflagrant.com')

report.ok?           # => true
report.http_status   # => 200
report.duration_ms   # => 834
report.network_errors  # => []   (Array<Perchfall::NetworkError>)
report.console_errors  # => []   (Array<Perchfall::ConsoleError>)
report.to_json # => '{"status":"ok","url":"https://example.com",...}'
