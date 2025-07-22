#!/usr/bin/env ruby
# pool_siege.rb
#
# Simple Connection Pool Load Tester - Like siege, but for Redis connection pools
#
# Usage:
#   ruby pool_siege.rb -t 20 -p 5 -o 100    # 20 threads, 5 pool size, 100 ops each
#   ruby pool_siege.rb --stress              # Find breaking point
#   ruby pool_siege.rb --light               # Quick validation

require 'optparse'
require 'io/console'
require_relative '../helpers/test_helpers'
require_relative 'lib/connection_pool_stress_test'

class PoolSiege
  def initialize(args)
    @options = parse_options(args)
    validate_options
  end

  def run
    setup_connection_pool
    print_test_description

    start_time = Time.now

    if @options[:quiet]
      run_silent_test
    else
      run_with_progress
    end

    end_time = Time.now
    print_final_results(end_time - start_time)
  end

  private

  def parse_options(args)
    options = {}

    OptionParser.new do |opts|
      opts.banner = "Usage: pool_siege.rb [options]"

      opts.on("-t", "--threads N", Integer, "Number of concurrent threads (default: 10)") do |n|
        options[:threads] = n
      end

      opts.on("-p", "--pool N", Integer, "Connection pool size (default: 5)") do |n|
        options[:pool_size] = n
      end

      opts.on("-o", "--ops N", Integer, "Operations per thread (default: 100)") do |n|
        options[:operations] = n
      end

      opts.on("-d", "--duration N", Integer, "Run for N seconds instead of fixed ops") do |n|
        options[:duration] = n
      end

      opts.on("-s", "--scenario NAME", String, "Test scenario (starvation, rapid_fire, long_transactions, mixed)") do |s|
        options[:scenario] = s.to_sym
      end

      opts.on("--light", "Quick validation (5 threads, 5 pool, 50 ops)") do
        options.merge!(threads: 5, pool_size: 5, operations: 50, scenario: :mixed_workload)
      end

      opts.on("--stress", "Find breaking point (50 threads, 5 pool, 100 ops)") do
        options.merge!(threads: 50, pool_size: 5, operations: 100, scenario: :pool_starvation)
      end

      opts.on("--production", "Realistic load (20 threads, 10 pool, 200 ops)") do
        options.merge!(threads: 20, pool_size: 10, operations: 200, scenario: :mixed_workload)
      end

      opts.on("-q", "--quiet", "Suppress progress, show only final results") do
        options[:quiet] = true
      end

      opts.on("-h", "--help", "Show this help") do
        puts opts
        puts ""
        puts "Examples:"
        puts "  pool_siege.rb --light           # Quick validation"
        puts "  pool_siege.rb --stress          # Find breaking point"
        puts "  pool_siege.rb -t 20 -p 5 -o 100 # Custom: 20 threads, 5 pool, 100 ops"
        puts "  pool_siege.rb -t 10 -d 30       # Run 10 threads for 30 seconds"
        puts ""
        puts "Scenarios:"
        puts "  starvation     - More threads than connections (tests queueing)"
        puts "  rapid_fire     - Minimal work per connection (tests throughput)"
        puts "  long_transactions - Hold connections longer (tests timeout behavior)"
        puts "  mixed          - Balanced workload (default)"
        exit
      end
    end.parse!(args)

    # Set defaults
    options[:threads] ||= 10
    options[:pool_size] ||= 5
    options[:operations] ||= 100
    options[:scenario] ||= :mixed_workload

    options
  end

  def validate_options
    if @options[:duration] && @options[:operations]
      puts "Error: Cannot specify both --ops and --duration"
      exit 1
    end

    if @options[:threads] < 1 || @options[:pool_size] < 1
      puts "Error: Threads and pool size must be positive integers"
      exit 1
    end

    valid_scenarios = [:pool_starvation, :rapid_fire, :long_transactions, :mixed_workload]
    unless valid_scenarios.include?(@options[:scenario])
      puts "Error: Invalid scenario. Valid options: #{valid_scenarios.join(', ')}"
      exit 1
    end
  end

  def setup_connection_pool
    pool_size = @options[:pool_size]

    Familia.class_eval do
      @@connection_pool = ConnectionPool.new(
        size: pool_size,
        timeout: 10
      ) do
        Redis.new(url: Familia.uri.to_s)
      end
    end
  end

  def print_test_description
    scenario_desc = case @options[:scenario]
                    when :pool_starvation
                      "Connection starvation test"
                    when :rapid_fire
                      "Rapid-fire operations test"
                    when :long_transactions
                      "Long-running transactions test"
                    when :mixed_workload
                      "Mixed workload test"
                    end

    if @options[:duration]
      puts "#{scenario_desc}: #{@options[:threads]} threads using #{@options[:pool_size]} connections for #{@options[:duration]}s"
    else
      total_ops = @options[:threads] * @options[:operations]
      puts "#{scenario_desc}: #{@options[:threads]} threads using #{@options[:pool_size]} connections, #{total_ops} total operations"
    end
    puts ""
  end

  def run_silent_test
    test = create_stress_test
    test.run
    @results = test.metrics.summary
  end

  def run_with_progress
    test = create_stress_test

    # Hook into the metrics collector to track progress
    total_ops = @options[:duration] ? nil : (@options[:threads] * @options[:operations])
    progress_tracker = ProgressTracker.new(total_ops)

    # Replace the metrics collector with our tracking version
    original_record = test.metrics.method(:record_operation)
    test.metrics.define_singleton_method(:record_operation) do |type, duration, success, wait_time = nil|
      original_record.call(type, duration, success, wait_time)
      progress_tracker.update(success)
    end

    # Start the test in a background thread
    test_thread = Thread.new { test.run }

    # Show progress while test runs
    progress_tracker.show_progress while test_thread.alive?
    test_thread.join

    progress_tracker.finish
    @results = test.metrics.summary
  end

  def create_stress_test
    config = {
      thread_count: @options[:threads],
      operations_per_thread: @options[:operations] || 9999, # Large number for duration-based
      pool_size: @options[:pool_size],
      pool_timeout: 10,
      operation_mix: :balanced,
      scenario: @options[:scenario]
    }

    if @options[:scenario] == :pool_starvation
      # For starvation test, use 2x threads as specified (like the original implementation)
      config[:thread_count] = @options[:pool_size] * 2 if @options[:scenario] == :pool_starvation
    end

    ConnectionPoolStressTest.new(config)
  end

  def print_final_results(elapsed_time)
    puts ""
    puts "Connection Pool Load Test Results:"
    puts "Transactions:               #{@results[:total_operations]} hits"
    puts "Availability:              #{@results[:success_rate]}%"
    puts "Elapsed time:              #{'%.2f' % elapsed_time} secs"
    puts "Response time:             #{'%.4f' % @results[:avg_duration]} secs"
    puts "Transaction rate:          #{'%.2f' % (@results[:total_operations] / elapsed_time)} trans/sec"
    puts "Avg connection wait:       #{'%.4f' % @results[:avg_wait_time]} secs"
    puts "Pool utilization:          #{'%.1f' % @results[:max_pool_utilization]}%"
    puts "Successful transactions:   #{@results[:successful_operations]}"
    puts "Failed transactions:       #{@results[:failed_operations]}"

    if @results[:failed_operations] > 0
      puts ""
      puts "Error breakdown:"
      @results[:errors_by_type].each do |error_type, count|
        puts "  #{error_type}: #{count}"
      end
    end

    # Simple health assessment
    puts ""
    if @results[:success_rate] >= 99.0
      puts "🟢 HEALTHY - Connection pool performing well"
    elsif @results[:success_rate] >= 95.0
      puts "🟡 DEGRADED - Some connection issues detected"
    else
      puts "🔴 CRITICAL - Significant connection pool problems"
    end
  end
end

# Simple progress tracker without external dependencies
class ProgressTracker
  def initialize(total_ops)
    @total_ops = total_ops
    @completed = 0
    @successful = 0
    @start_time = Time.now
    @last_update = Time.now
  end

  def update(success)
    @completed += 1
    @successful += 1 if success
  end

  def show_progress
    return unless should_update?

    if @total_ops
      show_ops_progress
    else
      show_time_progress
    end
  end

  def finish
    print "\r" + " " * 80 + "\r" # Clear progress line
  end

  private

  def should_update?
    now = Time.now
    return false if (now - @last_update) < 0.5 # Update at most every 500ms
    @last_update = now
    true
  end

  def show_ops_progress
    percent = (@completed.to_f / @total_ops * 100).round(1)
    success_rate = (@successful.to_f / @completed * 100).round(1) if @completed > 0
    elapsed = Time.now - @start_time
    rate = (@completed / elapsed).round(1) if elapsed > 0

    bar_width = 20
    filled = [(percent / 100.0 * bar_width).round, bar_width - 1].min
    spaces = [bar_width - filled - 1, 0].max
    bar = "=" * filled + ">" + " " * spaces

    progress_line = sprintf("\rProgress: [%s] %5.1f%% (%d/%d ops) | Success: %5.1f%% | Rate: %5.1f ops/sec",
                           bar, percent, @completed, @total_ops, success_rate || 0.0, rate || 0.0)

    print progress_line
  end

  def show_time_progress
    elapsed = Time.now - @start_time
    success_rate = (@successful.to_f / @completed * 100).round(1) if @completed > 0
    rate = (@completed / elapsed).round(1) if elapsed > 0

    progress_line = sprintf("\rRunning: %5.1fs | Operations: %d | Success: %5.1f%% | Rate: %5.1f ops/sec",
                           elapsed, @completed, success_rate || 0.0, rate || 0.0)

    print progress_line
  end
end

# Initialize Familia and run
if __FILE__ == $0
  Familia.debug = false
  BankAccount.redis.flushdb

  PoolSiege.new(ARGV).run
end
