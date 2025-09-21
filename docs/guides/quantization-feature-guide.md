# Quantization Feature Guide

## Overview

The Quantization feature provides time-based data bucketing capabilities for Familia objects. It allows you to round timestamps to specific intervals (quantums) and format them for consistent time-based data organization, analytics, and caching strategies.

## Core Concepts

### Quantum Intervals

A **quantum** is a time interval used to bucket timestamps. Common quantums include:

- **Minutes**: `1.minute`, `5.minutes`, `15.minutes`
- **Hours**: `1.hour`, `6.hours`, `12.hours`
- **Days**: `1.day`, `7.days`
- **Custom**: Any number of seconds (e.g., `90` for 1.5 minutes)

### Quantized Timestamps (qstamp)

The `qstamp` method generates quantized timestamps by:
1. Taking the current time (or specified time)
2. Rounding down to the nearest quantum boundary
3. Returning either a Unix timestamp (Integer) or formatted string

### Time Bucketing

Quantization enables consistent data bucketing across time periods:

```ruby
# All timestamps between 14:00:00 and 14:59:59 become 14:00:00
qstamp(1.hour, pattern: '%H:%M:%S', time: Time.parse('14:30:45'))  # => "14:00:00"
qstamp(1.hour, pattern: '%H:%M:%S', time: Time.parse('14:05:12'))  # => "14:00:00"
qstamp(1.hour, pattern: '%H:%M:%S', time: Time.parse('14:55:33'))  # => "14:00:00"
```

## Basic Usage

### Enabling Quantization

```ruby
class AnalyticsEvent < Familia::Horreum
  feature :quantization
  default_expiration 300  # 5 minutes (used as default quantum)

  identifier_field :event_id
  field :event_id, :event_type, :user_id, :data, :timestamp
end
```

### Simple Quantized Timestamps

```ruby
event = AnalyticsEvent.new

# Using default quantum (from default_expiration: 300 seconds)
timestamp = event.qstamp
# => 1687276800 (Unix timestamp rounded to 5-minute boundary)

# Using custom quantum
hourly_timestamp = event.qstamp(1.hour)
# => 1687276800 (rounded to hour boundary)

# Class-level qstamp (same functionality)
AnalyticsEvent.qstamp(1.hour)
# => 1687276800
```

### Formatted Timestamps

```ruby
# Generate formatted timestamp strings
hourly_key = AnalyticsEvent.qstamp(1.hour, pattern: '%Y%m%d%H')
# => "2023061514" (YYYYMMDDHH format)

daily_key = AnalyticsEvent.qstamp(1.day, pattern: '%Y-%m-%d')
# => "2023-06-15" (ISO date format)

weekly_key = AnalyticsEvent.qstamp(1.week, pattern: '%Y-W%U')
# => "2023-W24" (Year-Week format)
```

### Specifying Custom Time

```ruby
# Quantize a specific timestamp
specific_time = Time.utc(2023, 6, 15, 14, 30, 45)

quantized = AnalyticsEvent.qstamp(
  1.hour,
  pattern: '%Y-%m-%d %H:00:00',
  time: specific_time
)
# => "2023-06-15 14:00:00"
```

## Advanced Usage Patterns

### Time-Based Cache Keys

```ruby
class MetricsCache < Familia::Horreum
  feature :quantization

  identifier_field :cache_key
  field :cache_key, :data, :computed_at
  hashkey :hourly_metrics

  def self.hourly_cache_key(metric_type, time = nil)
    timestamp = qstamp(1.hour, pattern: '%Y%m%d%H', time: time)
    "metrics:#{metric_type}:#{timestamp}"
  end

  def self.daily_cache_key(metric_type, time = nil)
    timestamp = qstamp(1.day, pattern: '%Y%m%d', time: time)
    "metrics:#{metric_type}:daily:#{timestamp}"
  end
end

# Usage
hourly_key = MetricsCache.hourly_cache_key('page_views')
# => "metrics:page_views:2023061514"

daily_key = MetricsCache.daily_cache_key('signups')
# => "metrics:signups:daily:20230615"
```

### Analytics Data Bucketing

```ruby
class UserActivity < Familia::Horreum
  feature :quantization

  identifier_field :bucket_id
  field :bucket_id, :user_count, :event_count, :bucket_time

  def self.record_activity(user_id, event_type)
    # Create 15-minute activity buckets
    bucket_key = qstamp(15.minutes, pattern: '%Y%m%d%H%M')
    bucket_id = "activity:#{bucket_key}"

    # Find or create bucket
    bucket = find(bucket_id) || new(bucket_id: bucket_id, bucket_time: bucket_key)

    # Update metrics
    bucket.user_count ||= 0
    bucket.event_count ||= 0

    # Use Redis sets/hashes for precise counting
    bucket_users = bucket.related_set("users")
    bucket_users.add(user_id)

    bucket.user_count = bucket_users.count
    bucket.event_count += 1

    bucket.save
  end

  def self.activity_for_hour(hour_time)
    # Get all 15-minute buckets for the hour
    hour_start = qstamp(1.hour, time: hour_time)
    hour_pattern = Time.at(hour_start).strftime('%Y%m%d%H')

    # Find buckets matching the hour pattern
    bucket_keys = (0..3).map do |quarter|
      minute = quarter * 15
      Time.at(hour_start + (minute * 60)).strftime('%Y%m%d%H%M')
    end

    bucket_keys.map { |key| find("activity:#{key}") }.compact
  end
end

# Usage
UserActivity.record_activity('user_123', 'page_view')
hourly_buckets = UserActivity.activity_for_hour(Time.now)
```

### Time-Series Data Storage

```ruby
class TimeSeriesMetric < Familia::Horreum
  feature :quantization

  identifier_field :series_key
  field :series_key, :metric_name, :interval, :value, :timestamp
  zset :data_points  # Sorted set for time-ordered data

  def self.record_metric(metric_name, value, interval = 1.minute, time = nil)
    # Create consistent time bucket
    bucket_timestamp = qstamp(interval, time: time)
    series_key = "#{metric_name}:#{interval}"

    # Store in sorted set with timestamp as score
    metric = find(series_key) || new(
      series_key: series_key,
      metric_name: metric_name,
      interval: interval
    )

    metric.data_points.add(bucket_timestamp, value)
    metric.save

    metric
  end

  def self.get_series(metric_name, interval, start_time, end_time)
    series_key = "#{metric_name}:#{interval}"
    metric = find(series_key)
    return [] unless metric

    start_bucket = qstamp(interval, time: start_time)
    end_bucket = qstamp(interval, time: end_time)

    metric.data_points.rangebyscore(start_bucket, end_bucket, with_scores: true)
  end
end

# Usage - Record CPU usage every minute
TimeSeriesMetric.record_metric('cpu_usage', 75.5, 1.minute)
TimeSeriesMetric.record_metric('cpu_usage', 82.1, 1.minute, Time.now + 1.minute)

# Retrieve data for last hour
series_data = TimeSeriesMetric.get_series(
  'cpu_usage',
  1.minute,
  Time.now - 1.hour,
  Time.now
)
```

### Log Aggregation by Time

```ruby
class LogAggregator < Familia::Horreum
  feature :quantization

  identifier_field :log_bucket
  field :log_bucket, :level, :count, :first_seen, :last_seen
  hashkey :message_samples  # Store sample messages

  def self.aggregate_log(level, message, time = nil)
    # Create 5-minute buckets for log aggregation
    bucket_time = qstamp(5.minutes, time: time)
    bucket_id = "logs:#{level}:#{bucket_time}"

    aggregator = find(bucket_id) || new(
      log_bucket: bucket_id,
      level: level,
      count: 0,
      first_seen: bucket_time,
      last_seen: bucket_time
    )

    aggregator.count += 1
    aggregator.last_seen = Time.now.to_i

    # Keep sample messages (up to 10)
    sample_key = "sample_#{aggregator.count}"
    if aggregator.message_samples.count < 10
      aggregator.message_samples.hset(sample_key, message.truncate(200))
    end

    aggregator.save
    aggregator
  end

  def self.error_summary(time_range = 1.hour)
    start_time = Time.now - time_range
    end_time = Time.now

    # Find all error buckets in time range
    buckets = []
    current = qstamp(5.minutes, time: start_time)
    final = qstamp(5.minutes, time: end_time)

    while current <= final
      bucket_time = Time.at(current).strftime('%Y%m%d%H%M')
      error_bucket = find("logs:error:#{current}")
      buckets << error_bucket if error_bucket

      current += 5.minutes
    end

    {
      total_errors: buckets.sum(&:count),
      buckets: buckets,
      peak_bucket: buckets.max_by(&:count)
    }
  end
end
```

## Integration Patterns

### Rails Integration

```ruby
# config/initializers/quantization.rb
class ApplicationMetrics
  include Familia::Horreum
  feature :quantization

  # UnsortedSet up different quantum intervals for different metrics
  QUANTUM_CONFIGS = {
    real_time: 1.minute,    # High frequency metrics
    standard: 5.minutes,    # Regular analytics
    reporting: 1.hour,      # Hourly reports
    archival: 1.day        # Daily summaries
  }.freeze

  def self.metric_key(name, quantum_type = :standard, time = nil)
    quantum = QUANTUM_CONFIGS[quantum_type]
    timestamp = qstamp(quantum, pattern: '%Y%m%d%H%M', time: time)
    "metrics:#{name}:#{quantum_type}:#{timestamp}"
  end
end

# In your controllers/models
class MetricsCollector
  def self.track_page_view(page, user_id = nil)
    # Track at multiple granularities
    [:real_time, :standard, :reporting].each do |quantum_type|
      key = ApplicationMetrics.metric_key("page_views:#{page}", quantum_type)

      # Increment counter
      Familia.dbclient.incr(key)

      # UnsortedSet expiration based on quantum type
      ttl = case quantum_type
            when :real_time then 2.hours
            when :standard then 1.day
            when :reporting then 1.week
            end
      Familia.dbclient.expire(key, ttl)
    end
  end
end
```

### Background Job Integration

```ruby
class QuantizedDataProcessor
  include Sidekiq::Worker

  # Process data in quantized buckets every 5 minutes
  sidekiq_cron '*/5 * * * *'

  def perform
    # Process current 5-minute bucket
    current_bucket = AnalyticsEvent.qstamp(5.minutes)
    process_bucket(current_bucket)

    # Also process previous bucket in case of delayed data
    previous_bucket = AnalyticsEvent.qstamp(5.minutes, time: Time.now - 5.minutes)
    process_bucket(previous_bucket)
  end

  private

  def process_bucket(bucket_timestamp)
    bucket_key = Time.at(bucket_timestamp).strftime('%Y%m%d%H%M')

    # Find all events in this bucket
    events = AnalyticsEvent.all.select do |event|
      event_bucket = AnalyticsEvent.qstamp(5.minutes, time: Time.at(event.timestamp))
      event_bucket == bucket_timestamp
    end

    # Aggregate and store results
    aggregated = aggregate_events(events)
    store_aggregated_data(bucket_key, aggregated)
  end
end
```

### API Response Caching

```ruby
class CachedApiResponse < Familia::Horreum
  feature :quantization
  feature :expiration

  identifier_field :cache_key
  field :cache_key, :endpoint, :params_hash, :response_data
  default_expiration 15.minutes

  def self.cached_response(endpoint, params, cache_duration = 5.minutes)
    # Create cache key with quantized timestamp
    params_key = Digest::SHA256.hexdigest(params.to_json)
    timestamp = qstamp(cache_duration, pattern: '%Y%m%d%H%M')
    cache_key = "api:#{endpoint}:#{params_key}:#{timestamp}"

    # Try to find existing cache
    cached = find(cache_key)
    return JSON.parse(cached.response_data) if cached

    # Generate new response
    response_data = yield  # Block provides fresh data

    # Cache the response
    new_cache = new(
      cache_key: cache_key,
      endpoint: endpoint,
      params_hash: params_key,
      response_data: response_data.to_json
    )
    new_cache.save
    new_cache.update_expiration

    response_data
  end
end

# Usage in controller
class MetricsController < ApplicationController
  def dashboard_stats
    stats = CachedApiResponse.cached_response('/dashboard/stats', params, 1.minute) do
      # This block only runs if cache miss
      {
        active_users: User.active.count,
        total_orders: Order.today.count,
        revenue: Order.today.sum(:total)
      }
    end

    render json: stats
  end
end
```

## Quantum Calculation Examples

### Understanding Quantum Boundaries

```ruby
# Example with 1-hour quantum
time1 = Time.utc(2023, 6, 15, 14, 15, 30)  # 14:15:30
time2 = Time.utc(2023, 6, 15, 14, 45, 12)  # 14:45:12

hour_stamp1 = AnalyticsEvent.qstamp(1.hour, time: time1)
hour_stamp2 = AnalyticsEvent.qstamp(1.hour, time: time2)

# Both timestamps round down to 14:00:00
Time.at(hour_stamp1).strftime('%H:%M:%S')  # => "14:00:00"
Time.at(hour_stamp2).strftime('%H:%M:%S')  # => "14:00:00"
hour_stamp1 == hour_stamp2  # => true

# Example with 15-minute quantum
quarter1 = AnalyticsEvent.qstamp(15.minutes, time: time1)  # 14:15:30 -> 14:15:00
quarter2 = AnalyticsEvent.qstamp(15.minutes, time: time2)  # 14:45:12 -> 14:45:00

Time.at(quarter1).strftime('%H:%M:%S')  # => "14:15:00"
Time.at(quarter2).strftime('%H:%M:%S')  # => "14:45:00"
quarter1 == quarter2  # => false (different 15-minute buckets)
```

### Cross-Timezone Quantization

```ruby
class GlobalMetrics < Familia::Horreum
  feature :quantization

  def self.utc_hourly_key(time = nil)
    # Always quantize in UTC for global consistency
    utc_time = time&.utc || Time.now.utc
    qstamp(1.hour, pattern: '%Y%m%d%H', time: utc_time)
  end

  def self.local_daily_key(timezone, time = nil)
    # Quantize in local timezone for regional reports
    local_time = time || Time.now
    local_time = local_time.in_time_zone(timezone) if local_time.respond_to?(:in_time_zone)
    qstamp(1.day, pattern: '%Y%m%d', time: local_time)
  end
end

# Usage
utc_key = GlobalMetrics.utc_hourly_key  # Always consistent globally
ny_key = GlobalMetrics.local_daily_key('America/New_York')
tokyo_key = GlobalMetrics.local_daily_key('Asia/Tokyo')
```

## Performance Optimization

### Efficient Bucket Operations

```ruby
class OptimizedQuantization < Familia::Horreum
  feature :quantization

  # Cache quantum calculations
  def self.cached_qstamp(quantum, pattern: nil, time: nil)
    cache_key = "qstamp:#{quantum}:#{pattern}:#{time&.to_i}"

    Rails.cache.fetch(cache_key, expires_in: quantum) do
      qstamp(quantum, pattern: pattern, time: time)
    end
  end

  # Batch process multiple timestamps
  def self.batch_quantize(timestamps, quantum, pattern: nil)
    timestamps.map do |ts|
      qstamp(quantum, pattern: pattern, time: ts)
    end.uniq  # Remove duplicates from same bucket
  end

  # Pre-generate common buckets
  def self.pregenerate_buckets(quantum, count = 24)
    base_time = qstamp(quantum)  # Current bucket

    (0...count).map do |offset|
      bucket_time = base_time + (offset * quantum)
      Time.at(bucket_time).strftime('%Y%m%d%H%M')
    end
  end
end
```

### Memory-Efficient Storage

```ruby
class CompactTimeSeriesStorage < Familia::Horreum
  feature :quantization

  identifier_field :series_id
  field :series_id, :metric_name, :quantum

  # Store quantized data in Redis sorted sets for efficiency
  def record_value(value, time = nil)
    bucket_timestamp = self.class.qstamp(quantum, time: time)

    # Use timestamp as score, value as member
    data_key = "#{series_id}:data"
    Familia.dbclient.zadd(data_key, bucket_timestamp, value)

    # UnsortedSet TTL based on quantum (longer quantum = longer retention)
    ttl = calculate_retention_period
    Familia.dbclient.expire(data_key, ttl)
  end

  def get_range(start_time, end_time)
    start_bucket = self.class.qstamp(quantum, time: start_time)
    end_bucket = self.class.qstamp(quantum, time: end_time)

    data_key = "#{series_id}:data"
    Familia.dbclient.zrangebyscore(data_key, start_bucket, end_bucket, with_scores: true)
  end

  private

  def calculate_retention_period
    case quantum
    when 0..300 then 1.day      # Up to 5 minutes: keep 1 day
    when 301..3600 then 1.week  # Up to 1 hour: keep 1 week
    when 3601..86400 then 1.month # Up to 1 day: keep 1 month
    else 1.year                  # Longer: keep 1 year
    end
  end
end
```

## Testing Quantization

### RSpec Testing

```ruby
RSpec.describe AnalyticsEvent do
  describe "quantization behavior" do
    let(:test_time) { Time.utc(2023, 6, 15, 14, 30, 45) }

    it "quantizes to hour boundaries" do
      stamp = described_class.qstamp(1.hour, time: test_time)
      quantized_time = Time.at(stamp)

      expect(quantized_time.hour).to eq(14)
      expect(quantized_time.min).to eq(0)
      expect(quantized_time.sec).to eq(0)
    end

    it "generates consistent buckets for same period" do
      time1 = Time.utc(2023, 6, 15, 14, 10, 0)
      time2 = Time.utc(2023, 6, 15, 14, 50, 0)

      stamp1 = described_class.qstamp(1.hour, time: time1)
      stamp2 = described_class.qstamp(1.hour, time: time2)

      expect(stamp1).to eq(stamp2)
    end

    it "formats timestamps correctly" do
      formatted = described_class.qstamp(
        1.hour,
        pattern: '%Y-%m-%d %H:00',
        time: test_time
      )

      expect(formatted).to eq('2023-06-15 14:00')
    end

    it "uses default quantum from default_expiration" do
      allow(described_class).to receive(:default_expiration).and_return(300)

      stamp = described_class.qstamp

      # Should use 5-minute quantum (300 seconds)
      expect(stamp % 300).to eq(0)
    end
  end
end
```

### Integration Testing

```ruby
# Feature test for time-based caching
RSpec.feature "Quantized API Caching" do
  scenario "responses are cached within quantum boundaries" do
    travel_to Time.utc(2023, 6, 15, 14, 22, 30) do
      # First request
      get '/api/stats'
      first_response = JSON.parse(response.body)
      first_cache_key = extract_cache_key_from_headers(response)

      travel 2.minutes  # Still in same 5-minute bucket

      # Second request should use cache
      get '/api/stats'
      second_response = JSON.parse(response.body)
      second_cache_key = extract_cache_key_from_headers(response)

      expect(first_response).to eq(second_response)
      expect(first_cache_key).to eq(second_cache_key)

      travel 4.minutes  # Now in next 5-minute bucket

      # Third request should have new cache
      get '/api/stats'
      third_cache_key = extract_cache_key_from_headers(response)

      expect(third_cache_key).not_to eq(first_cache_key)
    end
  end
end
```

## Best Practices

### 1. Choose Appropriate Quantums

```ruby
# Match quantum to data characteristics
class MetricsConfig
  QUANTUM_RECOMMENDATIONS = {
    real_time_alerts: 1.minute,     # High frequency, short retention
    user_analytics: 5.minutes,      # Medium frequency, medium retention
    business_reports: 1.hour,       # Low frequency, long retention
    daily_summaries: 1.day,         # Summary data, permanent retention
    log_aggregation: 10.minutes     # Balance detail vs. performance
  }.freeze

  def self.quantum_for(metric_type)
    QUANTUM_RECOMMENDATIONS[metric_type] || 5.minutes
  end
end
```

### 2. Handle Edge Cases

```ruby
class RobustQuantization < Familia::Horreum
  feature :quantization

  def self.safe_qstamp(quantum, pattern: nil, time: nil)
    # Validate quantum
    quantum = quantum.to_f
    raise ArgumentError, "Quantum must be positive" unless quantum.positive?

    # Handle edge cases
    time ||= Familia.now
    time = Time.at(time) if time.is_a?(Numeric)

    # Generate timestamp
    qstamp(quantum, pattern: pattern, time: time)
  rescue => e
    # Fallback to current time with default quantum
    Rails.logger.warn "Quantization failed: #{e.message}"
    qstamp(300)  # 5-minute fallback
  end
end
```

### 3. Monitor Bucket Distribution

```ruby
class QuantizationMonitor
  def self.analyze_bucket_distribution(metric_name, quantum, time_range = 24.hours)
    buckets = {}
    current_time = Time.now - time_range
    end_time = Time.now

    while current_time <= end_time
      bucket = AnalyticsEvent.qstamp(quantum, time: current_time)
      buckets[bucket] ||= 0
      buckets[bucket] += 1  # Count events in this bucket

      current_time += quantum
    end

    {
      total_buckets: buckets.size,
      avg_events_per_bucket: buckets.values.sum.to_f / buckets.size,
      max_events_bucket: buckets.values.max,
      min_events_bucket: buckets.values.min,
      distribution: buckets
    }
  end
end
```

The Quantization feature provides powerful time-based data organization capabilities, enabling efficient analytics, caching, and time-series data management in Familia applications.
