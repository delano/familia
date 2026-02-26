# lib/familia/thread_safety/monitor.rb
#
# frozen_string_literal: true

require 'concurrent-ruby'

module Familia
  module ThreadSafety
    # Thread safety monitoring for production observability
    #
    # Tracks mutex contention, race conditions, and synchronization metrics
    # to provide insights into thread safety behavior in production.
    #
    # @example Basic usage
    #   Familia::ThreadSafety::Monitor.start!
    #   # ... application runs ...
    #   report = Familia::ThreadSafety::Monitor.report
    #   puts report[:summary]
    #
    # @example Custom instrumentation
    #   Familia::ThreadSafety::Monitor.record_contention('connection_chain')
    #   Familia::ThreadSafety::Monitor.time_critical_section('field_registration') do
    #     # ... critical code ...
    #   end
    class Monitor
      class << self
        def instance
          @instance ||= new
        end

        # Delegate all methods to singleton instance
        def method_missing(method, *args, &block)
          if instance.respond_to?(method)
            instance.send(method, *args, &block)
          else
            super
          end
        end

        def respond_to_missing?(method, include_private = false)
          instance.respond_to?(method) || super
        end
      end

      attr_reader :enabled, :started_at

      def initialize
        @enabled = false
        @started_at = nil
        @mutex_contentions = Concurrent::AtomicFixnum.new(0)
        @race_detections = Concurrent::AtomicFixnum.new(0)
        @critical_sections = Concurrent::AtomicFixnum.new(0)
        @deadlock_checks = Concurrent::AtomicFixnum.new(0)

        # Track contention points with counts
        @contention_points = Concurrent::Map.new

        # Track wait time aggregates for critical sections (removed @wait_times to prevent memory leak)
        @wait_time_totals = Concurrent::Map.new
        @wait_time_counts = Concurrent::Map.new

        # Track thread-local state for nested monitoring
        @thread_state = Concurrent::Map.new

        # Track concurrent operation counts
        @concurrent_operations = Concurrent::Map.new

        # Performance metrics
        @section_timings = Concurrent::Map.new
        @section_counts = Concurrent::Map.new
      end

      # Start monitoring
      def start!
        @enabled = true
        @started_at = Familia.now
        reset_metrics
        Familia.info("[ThreadSafety] Monitoring started")
        true
      end

      # Stop monitoring
      def stop!
        @enabled = false
        duration = @started_at ? Familia.now - @started_at : 0
        Familia.info("[ThreadSafety] Monitoring stopped after #{duration.round(2)}s")
        @started_at = nil
        true
      end

      # Reset all metrics
      def reset_metrics
        @mutex_contentions.value = 0
        @race_detections.value = 0
        @critical_sections.value = 0
        @deadlock_checks.value = 0
        @contention_points.clear
        # @wait_times.clear - removed to prevent memory leak
        @wait_time_totals.clear
        @wait_time_counts.clear
        @thread_state.clear
        @concurrent_operations.clear
        @section_timings.clear
        @section_counts.clear
      end

      # Record a mutex contention event
      def record_contention(location, wait_time = nil)
        return unless @enabled

        @mutex_contentions.increment
        @contention_points[location] = @contention_points.fetch(location, 0) + 1

        if wait_time
          record_wait_time(location, wait_time)
        end

        Familia.trace(:THREAD_CONTENTION, nil, "Contention at #{location} (wait: #{wait_time&.round(4)}s)")
      end

      # Record wait time for a location
      def record_wait_time(location, wait_time)
        # Note: @wait_times was removed to prevent memory leak from unbounded array growth
        # We only need the aggregated totals and counts for calculations
        @wait_time_totals[location] = @wait_time_totals.fetch(location, 0.0) + wait_time
        @wait_time_counts[location] = @wait_time_counts.fetch(location, 0) + 1
      end

      # Record a potential race condition detection
      def record_race_condition(location, details = nil)
        return unless @enabled

        @race_detections.increment
        msg = "Potential race condition at #{location}"
        msg += ": #{details}" if details
        Familia.warn("[ThreadSafety] #{msg}")
      end

      # Time a critical section with contention tracking
      def time_critical_section(name)
        return yield unless @enabled

        thread_id = Thread.current.object_id
        start_time = Familia.now_in_μs

        # Check for concurrent execution
        concurrent_count = @concurrent_operations[name] = @concurrent_operations.fetch(name, 0) + 1
        if concurrent_count > 1
          record_contention(name)
        end

        @critical_sections.increment

        begin
          result = yield
        ensure
          end_time = Familia.now_in_μs
          duration_μs = end_time - start_time

          # Record timing in microseconds
          @section_timings[name] = @section_timings.fetch(name, 0) + duration_μs
          @section_counts[name] = @section_counts.fetch(name, 0) + 1

          # Decrement concurrent count
          @concurrent_operations[name] = @concurrent_operations.fetch(name, 1) - 1

          if duration_μs > 100_000  # Log slow critical sections (> 100ms = 100,000μs)
            Familia.warn("[ThreadSafety] Slow critical section '#{name}': #{(duration_μs / 1000.0).round(2)}ms")
          end
        end

        result
      end

      # NOTE: monitor_mutex method was removed as it was unused and had flawed
      # exception handling that could lead to deadlocks. The InstrumentedMutex
      # class should be used instead for mutex monitoring.

      # Check for potential deadlocks
      def check_deadlock
        return unless @enabled

        @deadlock_checks.increment

        # This is a simple check - in production you might want more sophisticated detection
        thread_count = Thread.list.count
        if thread_count > 100
          Familia.warn("[ThreadSafety] High thread count: #{thread_count}")
        end

        # Check for threads waiting on mutexes (simplified)
        waiting_threads = Thread.list.select { |t| t.status == "sleep" }
        if waiting_threads.size > thread_count * 0.8
          Familia.warn("[ThreadSafety] Potential deadlock: #{waiting_threads.size}/#{thread_count} threads sleeping")
        end
      end

      # Generate a comprehensive report
      def report
        return { enabled: false, message: "Monitoring not enabled" } unless @started_at

        duration = Familia.now - @started_at

        # Calculate hot spots
        hot_spots = []
        @contention_points.each_pair do |location, count|
          hot_spots << [location, count]
        end
        hot_spots = hot_spots
          .sort_by { |_, count| -count }
          .first(10)
          .map { |location, count|
            avg_wait_μs = if @wait_time_counts[location] && @wait_time_counts[location] > 0
              (@wait_time_totals[location] / @wait_time_counts[location]).round(0)
            else
              0
            end
            {
              location: location,
              contentions: count,
              avg_wait_μs: avg_wait_μs
            }
          }

        # Calculate critical section performance
        section_performance = []
        @section_counts.each_pair do |name, count|
          avg_time_μs = (@section_timings[name] / count).round(0)
          section_performance << {
            section: name,
            calls: count,
            avg_time_μs: avg_time_μs,
            total_time_μs: @section_timings[name]
          }
        end
        section_performance.sort_by! { |s| -s[:total_time_μs] }

        {
          summary: {
            monitoring_duration_s: duration.round(2),
            mutex_contentions: @mutex_contentions.value,
            race_detections: @race_detections.value,
            critical_sections: @critical_sections.value,
            deadlock_checks: @deadlock_checks.value
          },
          hot_spots: hot_spots,
          section_performance: section_performance,
          health: calculate_health_score,
          recommendations: generate_recommendations(hot_spots)
        }
      end

      # Calculate a health score (0-100)
      def calculate_health_score
        return 100 unless @started_at

        duration = Familia.now - @started_at
        return 100 if duration < 60  # Need at least 1 minute of data

        contentions_per_hour = (@mutex_contentions.value / duration) * 3600
        races_per_hour = (@race_detections.value / duration) * 3600

        score = 100
        score -= [contentions_per_hour / 10.0, 30].min  # -3 points per 100 contentions/hour, max -30
        score -= [races_per_hour * 10, 50].min  # -10 points per race/hour, max -50

        [score, 0].max.round
      end

      # Generate recommendations based on metrics
      def generate_recommendations(hot_spots)
        recommendations = []

        if @race_detections.value > 0
          recommendations << {
            severity: 'critical',
            message: "#{@race_detections.value} potential race conditions detected - investigate immediately"
          }
        end

        if hot_spots.any? { |h| h[:contentions] > 100 }
          high_contention = hot_spots.select { |h| h[:contentions] > 100 }
          locations = high_contention.map { |h| h[:location] }.join(', ')
          recommendations << {
            severity: 'warning',
            message: "High contention detected at: #{locations}"
          }
        end

        if hot_spots.any? { |h| h[:avg_wait_μs] > 100_000 }  # > 100ms in microseconds
          slow_spots = hot_spots.select { |h| h[:avg_wait_μs] > 100_000 }
          recommendations << {
            severity: 'warning',
            message: "Long wait times at: #{slow_spots.map { |h| "#{h[:location]} (#{(h[:avg_wait_μs] / 1000.0).round(1)}ms)" }.join(', ')}"
          }
        end

        if @deadlock_checks.value > 0 && Thread.list.count > 50
          recommendations << {
            severity: 'info',
            message: "Consider connection pooling - high thread count detected"
          }
        end

        recommendations
      end

      # Export metrics in a format suitable for APM tools
      def export_metrics
        {
          'familia.thread_safety.mutex_contentions' => @mutex_contentions.value,
          'familia.thread_safety.race_detections' => @race_detections.value,
          'familia.thread_safety.critical_sections' => @critical_sections.value,
          'familia.thread_safety.deadlock_checks' => @deadlock_checks.value,
          'familia.thread_safety.health_score' => calculate_health_score
        }
      end

      # Hook for APM integration
      def apm_transaction(name, &block)
        return yield unless @enabled

        # This is where you'd integrate with NewRelic, DataDog, etc.
        time_critical_section(name, &block)
      end
    end
  end
end
