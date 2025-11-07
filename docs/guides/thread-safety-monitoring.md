Thread Safety Monitoring Usage Guide

### Development
```ruby
# Enable monitoring during local testing
Familia.start_monitoring!
# ... run your application ...
report = Familia.thread_safety_report
puts report[:hot_spots]  # See which mutexes are contentious
puts report[:recommendations]  # Get actionable insights
```

### CI/CD
```bash
# Add to test pipeline for race condition detection
FAMILIA_THREAD_SAFETY=1 bundle exec rspec
# Check for any race detections in CI logs
```

```ruby
# In test setup
if ENV['FAMILIA_THREAD_SAFETY']
  Familia.start_monitoring!
  at_exit do
    report = Familia.thread_safety_report
    if report[:summary][:race_detections] > 0
      puts "❌ Race conditions detected: #{report[:summary][:race_detections]}"
      exit 1
    end
  end
end
```

### Production
**APM Integration:**
```ruby
# Export metrics to DataDog, NewRelic, etc.
Thread.new do
  loop do
    metrics = Familia.thread_safety_metrics
    StatsD.gauge('familia.thread_safety.health_score', metrics['familia.thread_safety.health_score'])
    StatsD.count('familia.thread_safety.contentions', metrics['familia.thread_safety.mutex_contentions'])
    sleep 60
  end
end
```

**Health Check Endpoint:**
```ruby
# In Rails routes or Sinatra
get '/health/thread_safety' do
  report = Familia.thread_safety_report
  status = report[:health] >= 80 ? 200 : 503
  json report
end
```

**Key Alerts:**
- `health_score < 70` → Investigate contention
- `race_detections > 0` → Critical issue
- `avg_wait_ms > 100` → Performance problem
