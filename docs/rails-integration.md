# Rails integration

Perchfall has no Rails dependency — it works as a plain Ruby library. The recommended pattern is a background job that calls Perchfall and persists the result.

## Sidekiq job

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

## Database schema

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

## Querying results

```ruby
# Latest result for a URL
SyntheticResult.where(url: "https://example.com").order(checked_at: :desc).first

# All failures in the last hour
SyntheticResult.where(ok: false).where("checked_at > ?", 1.hour.ago)

# Availability over the last 24 hours
results = SyntheticResult.where("checked_at > ?", 24.hours.ago)
uptime = results.where(ok: true).count.to_f / results.count
```

## Scheduling

Use a cron-style scheduler (e.g. [Sidekiq-Cron](https://github.com/sidekiq-cron/sidekiq-cron) or [Whenever](https://github.com/javan/whenever)) to enqueue checks on a regular interval:

```ruby
# config/schedule.rb (Whenever)
every 5.minutes do
  runner "SyntheticCheckJob.perform_async('https://example.com', 'homepage')"
end
```
