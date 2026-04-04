# Framework integration

Perchfall has no framework dependency — it works as a plain Ruby library. These examples show common patterns for integrating it into popular Ruby web frameworks.

## Table of contents

- [Hanami](#hanami)
- [Rails](#rails)
- [Sinatra](#sinatra)
- [General notes](#general-notes)

## Hanami

Hanami 2.x applications can integrate Perchfall through an action for on-demand checks and a provider for dependency injection.

### Provider

```ruby
# config/providers/perchfall.rb
Hanami.app.register_provider(:perchfall) do
  start do
    require "perchfall"
    register "perchfall.client", Perchfall::Client.new
  end
end
```

### Action

```ruby
# app/actions/checks/create.rb
module MyApp
  module Actions
    module Checks
      class Create < MyApp::Action
        include Deps["perchfall.client"]

        params do
          required(:url).filled(:string)
          optional(:scenario).filled(:string)
        end

        def handle(request, response)
          halt 422, {error: "invalid params"}.to_json unless request.params.valid?

          report = client.run(
            url: request.params[:url],
            scenario_name: request.params[:scenario]
          )

          response.status = report.ok? ? 200 : 502
          response.format = :json
          response.body = report.to_json
        end
      end
    end
  end
end
```

### Background checks with a Rake task

```ruby
# Rakefile or lib/tasks/perchfall.rake
namespace :perchfall do
  desc "Run a synthetic check"
  task :check, [:url, :scenario] do |_t, args|
    require "perchfall"
    report = Perchfall.run!(url: args[:url], scenario_name: args[:scenario])
    puts "#{report.url} — #{report.ok? ? 'OK' : 'FAIL'} (#{report.duration_ms}ms)"
  end
end
```

Schedule with cron or any job scheduler:

```cron
*/5 * * * * cd /app && bundle exec rake perchfall:check[https://example.com,homepage]
```

## Rails

The recommended pattern is a background job that calls Perchfall and persists the result.

### Sidekiq job

```ruby
# app/jobs/synthetic_check_job.rb
class SyntheticCheckJob
  include Sidekiq::Job

  def perform(url, scenario_name = nil)
    report = Perchfall.run(url: url, scenario_name: scenario_name)
    SyntheticResult.create!(
      url:           report.url,
      scenario_name: report.scenario_name,
      ok:            report.ok?,
      http_status:   report.http_status,
      duration_ms:   report.duration_ms,
      payload:       report.to_json,
      checked_at:    report.timestamp
    )
  rescue Perchfall::Errors::PageLoadError => e
    SyntheticResult.create!(
      url:        e.report.url,
      ok:         false,
      payload:    e.report.to_json,
      checked_at: e.report.timestamp
    )
  end
end
```

Enqueue from anywhere:

```ruby
SyntheticCheckJob.perform_async("https://example.com", "homepage")
SyntheticCheckJob.perform_in(5.minutes, "https://example.com/checkout", "checkout_flow")
```

### Database schema

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_synthetic_results.rb
create_table :synthetic_results do |t|
  t.string   :url,           null: false
  t.string   :scenario_name
  t.boolean  :ok,            null: false
  t.integer  :http_status
  t.integer  :duration_ms
  t.jsonb    :payload,       null: false   # full Perchfall report JSON
  t.datetime :checked_at,    null: false
  t.timestamps
end

add_index :synthetic_results, [:url, :checked_at]
add_index :synthetic_results, :ok
```

### Querying results

```ruby
# Latest result for a URL
SyntheticResult.where(url: "https://example.com").order(checked_at: :desc).first

# All failures in the last hour
SyntheticResult.where(ok: false).where("checked_at > ?", 1.hour.ago)

# Availability over the last 24 hours
results = SyntheticResult.where("checked_at > ?", 24.hours.ago)
uptime = results.where(ok: true).count.to_f / results.count
```

### Scheduling

Use a cron-style scheduler (e.g. [Sidekiq-Cron](https://github.com/sidekiq-cron/sidekiq-cron) or [Whenever](https://github.com/javan/whenever)) to enqueue checks on a regular interval:

```ruby
# config/schedule.rb (Whenever)
every 5.minutes do
  runner "SyntheticCheckJob.perform_async('https://example.com', 'homepage')"
end
```

## Sinatra

In Sinatra, run checks inline for on-demand use or offload to a thread/background worker for periodic monitoring.

### On-demand endpoint

```ruby
# app.rb
require "sinatra"
require "perchfall"
require "json"

post "/checks" do
  content_type :json
  report = Perchfall.run(url: params[:url], scenario_name: params[:scenario])
  status report.ok? ? 200 : 502
  report.to_json
end
```

### Background thread for periodic checks

```ruby
# config.ru
require "./app"

Thread.new do
  loop do
    report = Perchfall.run(url: "https://example.com")
    $last_report = report
    sleep 300
  end
end

run Sinatra::Application
```

For production use, pair with a job processor like [Sucker Punch](https://github.com/brandonhilkert/sucker_punch) (no external deps) or Sidekiq with the `sidekiq` gem.

## General notes

- **Perchfall launches Chromium** — avoid running checks inside web request threads in production. Offload to background jobs or workers.
- **Concurrency** — Perchfall caps simultaneous Chromium instances to 5 by default. Override by injecting a custom `ConcurrencyLimiter` into `Client.new`.
- **Error handling** — `Perchfall.run` always returns a `Report` (check `report.ok?`). Use `Perchfall.run!` to raise `Perchfall::Errors::PageLoadError` on failure.
