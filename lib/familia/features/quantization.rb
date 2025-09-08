# lib/familia/features/quantization.rb

module Familia
  module Features
    # Quantization is a feature that provides time-based data bucketing and quantized
    # timestamp generation for Familia objects. It enables efficient time-series data
    # storage, analytics aggregation, and temporal cache key generation by rounding
    # timestamps to specific intervals.
    #
    # This feature is particularly useful for:
    # - Time-series data collection and storage
    # - Analytics data bucketing by time intervals
    # - Cache key generation with time-based expiration
    # - Log aggregation by time periods
    # - Metrics collection with reduced granularity
    # - Rate limiting with time windows
    #
    # Example:
    #
    #   class AnalyticsEvent < Familia::Horreum
    #     feature :quantization
    #     default_expiration 1.hour  # Used as default quantum
    #
    #     identifier_field :event_id
    #     field :event_id, :event_type, :user_id, :data, :timestamp
    #   end
    #
    #   # Generate quantized timestamps
    #   AnalyticsEvent.qstamp(1.hour)           # => 1672531200 (rounded to hour)
    #   AnalyticsEvent.qstamp(1.hour, '%Y%m%d%H') # => "2023010114" (formatted)
    #   AnalyticsEvent.qstamp([1.hour, '%Y%m%d%H']) # => "2023010114" (array syntax)
    #
    #   # Instance method also available
    #   event = AnalyticsEvent.new
    #   event.qstamp(15.minutes)                # => 1672531800 (15-min buckets)
    #
    # Time Bucketing:
    #
    # Quantization rounds timestamps to specific intervals, creating consistent
    # time buckets for data aggregation:
    #
    #   # Current time: 2023-01-01 14:37:42
    #   User.qstamp(1.hour)     # => 1672531200 (14:00:00)
    #   User.qstamp(15.minutes) # => 1672532100 (14:35:00)
    #   User.qstamp(1.day)      # => 1672531200 (00:00:00)
    #
    # Formatted Timestamps:
    #
    # Use strftime patterns to generate formatted timestamp strings:
    #
    #   User.qstamp(1.hour, pattern: '%Y%m%d%H')     # => "2023010114"
    #   User.qstamp(1.day, pattern: '%Y-%m-%d')      # => "2023-01-01"
    #   User.qstamp(1.week, pattern: '%Y-W%W')       # => "2023-W01"
    #
    # Custom Time Reference:
    #
    # Specify a custom time instead of using the current time:
    #
    #   custom_time = Time.parse('2023-06-15 14:30:45')
    #   User.qstamp(1.hour, time: custom_time)      # => 1686834000 (14:00:00)
    #   User.qstamp(1.day, time: custom_time, pattern: '%Y%m%d') # => "20230615"
    #
    # Integration Patterns:
    #
    #   # Time-based cache keys
    #   class MetricsCache < Familia::Horreum
    #     feature :quantization
    #     identifier_field :cache_key
    #
    #     field :cache_key, :data, :computed_at
    #     hashkey :hourly_metrics
    #
    #     def self.hourly_cache_key(metric_name)
    #       timestamp = qstamp(1.hour, pattern: '%Y%m%d%H')
    #       "metrics:#{metric_name}:#{timestamp}"
    #     end
    #
    #     def self.daily_cache_key(metric_name)
    #       timestamp = qstamp(1.day, pattern: '%Y%m%d')
    #       "daily_metrics:#{metric_name}:#{timestamp}"
    #     end
    #   end
    #
    #   # Usage
    #   hourly_key = MetricsCache.hourly_cache_key('page_views')
    #   # => "metrics:page_views:2023010114"
    #
    #   # Analytics data bucketing
    #   class UserActivity < Familia::Horreum
    #     feature :quantization
    #     identifier_field :bucket_id
    #
    #     field :bucket_id, :user_count, :event_count, :bucket_time
    #
    #     def self.record_activity(user_id, event_type)
    #       # Create hourly buckets
    #       bucket_time = qstamp(1.hour)
    #       bucket_id = "activity:#{qstamp(1.hour, pattern: '%Y%m%d%H')}"
    #
    #       activity = find_or_create(bucket_id) do
    #         new(bucket_id: bucket_id, bucket_time: bucket_time,
    #             user_count: 0, event_count: 0)
    #       end
    #
    #       activity.event_count += 1
    #       activity.save
    #     end
    #
    #     def self.activity_for_hour(time = Time.now)
    #       bucket_id = "activity:#{qstamp(1.hour, time: time, pattern: '%Y%m%d%H')}"
    #       find(bucket_id)
    #     end
    #   end
    #
    #   # Time-series data storage
    #   class TimeSeriesMetric < Familia::Horreum
    #     feature :quantization
    #     identifier_field :series_key
    #
    #     field :series_key, :metric_name, :interval, :value, :timestamp
    #     zset :data_points  # score = timestamp, member = value
    #
    #     def self.record_metric(metric_name, value, interval = 5.minutes)
    #       timestamp = qstamp(interval)
    #       series_key = "#{metric_name}:#{interval.to_i}"
    #
    #       metric = find_or_create(series_key) do
    #         new(series_key: series_key, metric_name: metric_name,
    #             interval: interval.to_i)
    #       end
    #
    #       metric.data_points.add(timestamp, value)
    #       metric.timestamp = timestamp
    #       metric.value = value
    #       metric.save
    #     end
    #
    #     def self.get_series(metric_name, interval, start_time, end_time)
    #       series_key = "#{metric_name}:#{interval.to_i}"
    #       metric = find(series_key)
    #       return [] unless metric
    #
    #       start_bucket = qstamp(interval, time: start_time)
    #       end_bucket = qstamp(interval, time: end_time)
    #       metric.data_points.range_by_score(start_bucket, end_bucket, with_scores: true)
    #     end
    #   end
    #
    # Quantum Calculation:
    #
    # The quantum (time interval) determines the bucket size:
    # - 1.minute: Buckets every minute (00, 01, 02, ...)
    # - 5.minutes: Buckets every 5 minutes (00, 05, 10, 15, ...)
    # - 1.hour: Buckets every hour (00:00, 01:00, 02:00, ...)
    # - 1.day: Daily buckets (00:00:00 each day)
    # - 1.week: Weekly buckets (start of week)
    #
    # Understanding Quantum Boundaries:
    #
    #   # Current time: 2023-01-01 14:37:42
    #
    #   # 1.hour quantum (rounds down to hour boundary)
    #   qstamp(1.hour)  # => 1672531200 (2023-01-01 14:00:00)
    #
    #   # 15.minutes quantum (rounds down to 15-minute boundary)
    #   qstamp(15.minutes)  # => 1672532100 (2023-01-01 14:30:00)
    #
    #   # 1.day quantum (rounds down to day boundary)
    #   qstamp(1.day)  # => 1672531200 (2023-01-01 00:00:00)
    #
    # Cross-Timezone Considerations:
    #
    #   class GlobalMetrics < Familia::Horreum
    #     feature :quantization
    #
    #     def self.utc_hourly_key(metric_name)
    #       # Always use UTC for consistent global buckets
    #       timestamp = qstamp(1.hour, time: Time.now.utc, pattern: '%Y%m%d%H')
    #       "global:#{metric_name}:#{timestamp}"
    #     end
    #
    #     def self.local_daily_key(metric_name, timezone = 'America/New_York')
    #       # Use local timezone for region-specific buckets
    #       local_time = Time.now.in_time_zone(timezone)
    #       timestamp = qstamp(1.day, time: local_time, pattern: '%Y%m%d')
    #       "#{timezone.gsub('/', '_')}:#{metric_name}:#{timestamp}"
    #     end
    #   end
    #
    # Performance Optimization:
    #
    #   class OptimizedQuantization < Familia::Horreum
    #     feature :quantization
    #
    #     # Cache quantized timestamps to avoid repeated calculations
    #     def self.cached_qstamp(quantum, pattern: nil, time: nil)
    #       cache_key = "qstamp:#{quantum}:#{pattern}:#{(time || Time.now).to_i / quantum}"
    #       Rails.cache.fetch(cache_key, expires_in: quantum) do
    #         qstamp(quantum, pattern: pattern, time: time)
    #       end
    #     end
    #
    #     # Batch quantize multiple timestamps
    #     def self.batch_quantize(timestamps, quantum)
    #       timestamps.map { |ts| Familia.qstamp(quantum, time: ts) }
    #     end
    #
    #     # Pre-generate bucket timestamps for a time range
    #     def self.pregenerate_buckets(start_time, end_time, quantum)
    #       buckets = []
    #       current = Familia.qstamp(quantum, time: start_time)
    #       end_bucket = Familia.qstamp(quantum, time: end_time)
    #
    #       while current <= end_bucket
    #         buckets << current
    #         current += quantum
    #       end
    #       buckets
    #     end
    #   end
    #
    # Error Handling:
    #
    # The feature validates quantum values and provides descriptive errors:
    #
    #   User.qstamp(0)        # => ArgumentError: Quantum must be positive
    #   User.qstamp(-5)       # => ArgumentError: Quantum must be positive
    #   User.qstamp("invalid") # => ArgumentError: Quantum must be positive
    #
    # Default Quantum Behavior:
    #
    # If no quantum is specified, the feature uses default_expiration or 10.minutes:
    #
    #   class MyModel < Familia::Horreum
    #     feature :quantization
    #     default_expiration 1.hour
    #   end
    #
    #   MyModel.qstamp()  # Uses 1.hour as quantum
    #
    #   class NoDefault < Familia::Horreum
    #     feature :quantization
    #   end
    #
    #   NoDefault.qstamp()  # Uses 10.minutes as fallback quantum
    #
    module Quantization

      using Familia::Refinements::TimeLiterals

      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods
      end

      # Familia::Quantization::ClassMethods
      #
      module ClassMethods
        # Generates a quantized timestamp based on the given parameters
        #
        # This method rounds the current time to the nearest quantum and optionally
        # formats it according to the given pattern. It's useful for creating
        # time-based buckets or keys with reduced granularity.
        #
        # @param quantum [Numeric, Array, nil] The time quantum in seconds or an array of [quantum, pattern]
        # @param pattern [String, nil] The strftime pattern to format the timestamp
        # @param time [Time, nil] The reference time (default: current time)
        # @return [Integer, String] A unix timestamp or formatted timestamp string
        #
        # @example Generate hourly bucket timestamp
        #   User.qstamp(1.hour)  # => 1672531200 (rounded to hour boundary)
        #
        # @example Generate formatted timestamp
        #   User.qstamp(1.hour, pattern: '%Y%m%d%H')  # => "2023010114"
        #
        # @example Using array syntax
        #   User.qstamp([1.hour, '%Y%m%d%H'])  # => "2023010114"
        #
        # @example With custom time reference
        #   custom_time = Time.parse('2023-06-15 14:30:45')
        #   User.qstamp(1.hour, time: custom_time)  # => 1686834000
        #
        # @raise [ArgumentError] If quantum is not positive
        #
        def qstamp(quantum = nil, pattern: nil, time: nil)
          # Handle array input format: [quantum, pattern]
          if quantum.is_a?(Array)
            quantum, pattern = quantum
          end

          # Use default quantum if none specified
          # Priority: provided quantum > class default_expiration > 10.minutes fallback
          quantum ||= default_expiration || 10.minutes

          # Validate quantum value
          unless quantum.is_a?(Numeric) && quantum.positive?
            raise ArgumentError, "Quantum must be positive (#{quantum.inspect} given)"
          end

          # Delegate to Familia.qstamp for the actual calculation
          Familia.qstamp(quantum, pattern: pattern, time: time)
        end

        # Generate multiple quantized timestamps for a time range
        #
        # @param start_time [Time] Start of the time range
        # @param end_time [Time] End of the time range
        # @param quantum [Numeric] Time quantum in seconds
        # @param pattern [String, nil] Optional strftime pattern
        # @return [Array] Array of quantized timestamps
        #
        # @example Generate hourly buckets for a day
        #   start_time = Time.parse('2023-01-01 00:00:00')
        #   end_time = Time.parse('2023-01-01 23:59:59')
        #   User.qstamp_range(start_time, end_time, 1.hour)
        #   # => [1672531200, 1672534800, 1672538400, ...] (24 hourly buckets)
        #
        def qstamp_range(start_time, end_time, quantum, pattern: nil)
          timestamps = []
          current = qstamp(quantum, time: start_time)
          end_bucket = qstamp(quantum, time: end_time)

          while current <= end_bucket
            if pattern
              timestamps << Time.at(current).strftime(pattern)
            else
              timestamps << current
            end
            current += quantum
          end

          timestamps
        end

        # Check if a timestamp falls within a quantized bucket
        #
        # @param timestamp [Time, Integer] The timestamp to check
        # @param quantum [Numeric] The quantum interval
        # @param bucket_time [Time, Integer] The bucket reference time
        # @return [Boolean] true if timestamp falls in the bucket
        #
        # @example Check if event falls in hourly bucket
        #   event_time = Time.parse('2023-01-01 14:37:42')
        #   bucket_time = Time.parse('2023-01-01 14:00:00')
        #   User.in_bucket?(event_time, 1.hour, bucket_time)  # => true
        #
        def in_bucket?(timestamp, quantum, bucket_time)
          timestamp = timestamp.to_i if timestamp.respond_to?(:to_i)
          bucket_time = bucket_time.to_i if bucket_time.respond_to?(:to_i)
          bucket_start = qstamp(quantum, time: Time.at(bucket_time))
          bucket_end = bucket_start + quantum - 1

          timestamp >= bucket_start && timestamp <= bucket_end
        end
      end

      # Instance method version of qstamp
      #
      # Generates a quantized timestamp using the same logic as the class method,
      # but can access instance-specific default expiration settings.
      #
      # @param quantum [Numeric, Array, nil] The time quantum in seconds or array format
      # @param pattern [String, nil] The strftime pattern to format the timestamp
      # @param time [Time, nil] The reference time (default: current time)
      # @return [Integer, String] A unix timestamp or formatted timestamp string
      #
      # @example Instance usage
      #   event = AnalyticsEvent.new
      #   event.qstamp(15.minutes)  # => 1672532100
      #
      def qstamp(quantum = nil, pattern: nil, time: nil)
        # Use instance default_expiration if available, otherwise delegate to class
        quantum ||= default_expiration if respond_to?(:default_expiration)
        self.class.qstamp(quantum, pattern: pattern, time: time)
      end

      # Generate a quantized identifier for this instance
      #
      # Creates a time-based identifier using the instance's identifier and
      # a quantized timestamp. Useful for creating time-bucketed cache keys
      # or grouping identifiers.
      #
      # @param quantum [Numeric] Time quantum in seconds
      # @param pattern [String, nil] Optional strftime pattern
      # @param separator [String] Separator between identifier and timestamp
      # @return [String] Combined identifier with quantized timestamp
      #
      # @example Generate time-based cache key
      #   user = User.new(id: 123)
      #   user.quantized_identifier(1.hour)  # => "123:1672531200"
      #   user.quantized_identifier(1.hour, pattern: '%Y%m%d%H')  # => "123:2023010114"
      #
      def quantized_identifier(quantum, pattern: nil, separator: ':')
        timestamp = qstamp(quantum, pattern: pattern)
        base_id = respond_to?(:identifier) ? identifier : object_id
        "#{base_id}#{separator}#{timestamp}"
      end

      extend ClassMethods

      Familia::Base.add_feature self, :quantization
    end
  end
end
