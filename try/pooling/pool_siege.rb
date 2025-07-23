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

    if @options[:profile]
      run_with_profiling
    else
      start_time = Time.now

      if @options[:quiet]
        run_silent_test
      else
        run_with_progress
      end

      end_time = Time.now
      print_final_results(end_time - start_time)
    end
  end

  private

  def percentile(values, percentile)
    return 0 if values.empty?
    sorted = values.sort
    index = (percentile * (sorted.size - 1)).round
    sorted[index]
  end

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

      opts.on("-a", "--accounts N", Integer, "Number of shared accounts for all threads (default: one per thread)") do |n|
        options[:shared_accounts] = n
      end

      opts.on("--fresh-records", "Create a new account for every operation (tests record creation load)") do
        options[:fresh_records] = true
      end

      opts.on("-m", "--threading-model MODEL", "Threading model: traditional, fiber, thread_pool, hybrid, actor") do |model|
        valid_models = %w[traditional fiber thread_pool hybrid actor]
        unless valid_models.include?(model)
          puts "Invalid threading model: #{model}. Valid options: #{valid_models.join(', ')}"
          exit 1
        end
        options[:threading_model] = model.to_sym
      end

      opts.on("--light", "Light load validation (5 threads, 5 pool, 50 ops)") do
        options.merge!(threads: 5, pool_size: 5, operations: 50, scenario: :mixed_workload)
      end

      opts.on("--quick", "Quick validation (2 threads, 2 pool, 10 ops)") do
        options.merge!(threads: 2, pool_size: 2, operations: 10, scenario: :mixed_workload)
      end

      opts.on("--stress", "Find breaking point (50 threads, 5 pool, 100 ops)") do
        options.merge!(threads: 50, pool_size: 5, operations: 100, scenario: :pool_starvation)
      end

      opts.on("--production", "Realistic load (20 threads, 10 pool, 200 ops)") do
        options.merge!(threads: 20, pool_size: 10, duration: 5, scenario: :mixed_workload)
      end

      opts.on("-q", "--quiet", "Suppress progress, show only final results") do
        options[:quiet] = true
      end

      opts.on("--profile", "Enable profiling for performance analysis") do
        options[:profile] = true
      end

      opts.on("-h", "--help", "Show this help") do
        puts opts
        puts ""
        puts "Examples:"
        puts "  pool_siege.rb --light           # Quick validation"
        puts "  pool_siege.rb --stress          # Find breaking point"
        puts "  pool_siege.rb -t 20 -p 5 -o 100 # Custom: 20 threads, 5 pool, 100 ops"
        puts "  pool_siege.rb -t 10 -d 30       # Run 10 threads for 30 seconds"
        puts "  pool_siege.rb -t 20 -a 3        # 20 threads contending over 3 shared accounts"
        puts "  pool_siege.rb --light --fresh-records # Create new account for every operation"
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
    options[:operations] ||= 100 unless options[:duration]
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

    if @options[:shared_accounts]
      puts "High-contention mode: #{@options[:threads]} threads contending over #{@options[:shared_accounts]} shared accounts"
    elsif @options[:fresh_records]
      puts "Fresh records mode: Creating new account for every operation"
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
    # progress_tracker.show_progress while test_thread.alive?
    while test_thread.alive?
      progress_tracker.show_progress
      sleep(0.5)  # Sleep 100ms between progress updates
    end

    test_thread.join

    progress_tracker.finish
    @results = test.metrics.summary
  end

  def run_with_profiling
    puts "🔍 Running with lightweight performance profiling..."

    # Simple profiling data collection
    profile_data = {
      operation_times: [],
      connection_wait_times: [],
      redis_operation_times: [],
      method_counts: Hash.new(0)
    }

    # Monkey patch to collect timing data
    original_atomic = Familia.method(:atomic)
    Familia.define_singleton_method(:atomic) do |&block|
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      wait_start = start_time

      result = nil
      connection_pool.with do |conn|
        wait_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        profile_data[:connection_wait_times] << (wait_end - wait_start) * 1000

        op_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          self.current_transaction = conn
          result = yield
        ensure
          self.current_transaction = nil
        end
        op_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        profile_data[:redis_operation_times] << (op_end - op_start) * 1000
      end

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      profile_data[:operation_times] << (end_time - start_time) * 1000
      profile_data[:method_counts][:atomic] += 1

      result
    end

    # Run the test
    start_time = Time.now
    run_silent_test
    end_time = Time.now
    total_time = end_time - start_time

    # Restore original method
    Familia.define_singleton_method(:atomic, original_atomic)

    # Generate report
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    scenario_name = @options[:scenario].to_s
    report_file = "pool_siege_#{scenario_name}_#{timestamp}_profile.txt"

    File.open(report_file, 'w') do |f|
      f.puts "Pool Siege Lightweight Profiling Report"
      f.puts "=" * 50
      f.puts "Scenario: #{scenario_name}"
      f.puts "Total Time: #{total_time.round(3)}s"
      f.puts "Total Operations: #{profile_data[:method_counts][:atomic]}"
      f.puts ""

      if profile_data[:operation_times].any?
        f.puts "Operation Timing (ms):"
        f.puts "  Average: #{(profile_data[:operation_times].sum / profile_data[:operation_times].size).round(3)}"
        f.puts "  Min: #{profile_data[:operation_times].min.round(3)}"
        f.puts "  Max: #{profile_data[:operation_times].max.round(3)}"
        f.puts "  P95: #{percentile(profile_data[:operation_times], 0.95).round(3)}"
        f.puts ""
      end

      if profile_data[:connection_wait_times].any?
        f.puts "Connection Pool Wait Time (ms):"
        f.puts "  Average: #{(profile_data[:connection_wait_times].sum / profile_data[:connection_wait_times].size).round(3)}"
        f.puts "  Min: #{profile_data[:connection_wait_times].min.round(3)}"
        f.puts "  Max: #{profile_data[:connection_wait_times].max.round(3)}"
        f.puts "  P95: #{percentile(profile_data[:connection_wait_times], 0.95).round(3)}"
        f.puts ""
      end

      if profile_data[:redis_operation_times].any?
        f.puts "Redis Operation Time (ms):"
        f.puts "  Average: #{(profile_data[:redis_operation_times].sum / profile_data[:redis_operation_times].size).round(3)}"
        f.puts "  Min: #{profile_data[:redis_operation_times].min.round(3)}"
        f.puts "  Max: #{profile_data[:redis_operation_times].max.round(3)}"
        f.puts "  P95: #{percentile(profile_data[:redis_operation_times], 0.95).round(3)}"
      end
    end

    # Show results
    print_final_results(total_time)

    puts ""
    puts "📊 Lightweight Profiling Complete:"
    puts "   Report: #{report_file}"
    puts ""
    puts "💡 View the report with: cat #{report_file}"
  end

  def create_stress_test
    config = {
      thread_count: @options[:threads],
      operations_per_thread: @options[:operations],
      pool_size: @options[:pool_size],
      pool_timeout: 10,
      duration: @options[:duration],
      operation_mix: :balanced,
      scenario: @options[:scenario],
      shared_accounts: @options[:shared_accounts], # Pass through the shared accounts option
      fresh_records: @options[:fresh_records] # Pass through the fresh records option
    }

    if @options[:scenario] == :pool_starvation
      # For starvation test, use 2x threads as specified (like the original implementation)
      config[:thread_count] = @options[:pool_size] * 2 if @options[:scenario] == :pool_starvation
    end

    # Use enhanced version if threading model specified
    if @options[:threading_model] && @options[:threading_model] != :traditional
      require_relative 'lib/connection_pool_threading_models'
      config[:threading_model] = @options[:threading_model]
      EnhancedConnectionPoolStressTest.new(config)
    else
      ConnectionPoolStressTest.new(config)
    end
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
