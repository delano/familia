# try/prototypes/connection_pool_stress_test.rb
#
# Connection Pool Stress Test Framework
#
# This stress test validates the connection pool implementation under various
# threading models and load conditions. It aims to identify failure modes,
# bottlenecks, and ensure predictable behavior under pressure.
#
# Key Testing Dimensions:
# - Threading models (Threads, Fibers, Thread Pools)
# - Load patterns (read-heavy, write-heavy, transaction-heavy)
# - Pool configurations (size, timeout)
# - Failure scenarios (starvation, timeouts, errors)

require 'bundler/setup'
require 'securerandom'
require 'thread'
require 'fiber'

begin
  require 'csv'
rescue LoadError
  puts "CSV gem not available, using basic output"
end

begin
  require 'concurrent-ruby'
rescue LoadError
  puts "concurrent-ruby gem not available, falling back to mutex-based metrics"
end

require_relative '../../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

# Stress Test Configuration - Central hub for all testing parameters
module StressTestConfig
  # Threading Configuration
  THREAD_COUNTS = [5, 10, 50, 100]
  FIBER_COUNTS = [10, 50, 100, 500]
  WORKER_POOL_SIZES = [5, 10, 20]

  # Operations Configuration
  OPERATIONS_PER_THREAD = [10, 100, 500]

  # Connection Pool Configuration
  POOL_SIZES = [5, 10, 20, 50]
  POOL_TIMEOUTS = [1, 5, 10] # seconds

  # Operation Types
  OPERATION_MIXES = {
    read_heavy: { read: 80, write: 15, transaction: 5 },
    write_heavy: { read: 20, write: 70, transaction: 10 },
    transaction_heavy: { read: 10, write: 20, transaction: 70 },
    balanced: { read: 33, write: 33, transaction: 34 }
  }

  # Test Scenarios
  SCENARIOS = [
    :pool_starvation,      # More threads than connections
    :rapid_fire,           # Minimal work per connection
    :long_transactions,    # Hold connections longer
    :nested_transactions,  # Test transaction isolation
    :error_injection,      # Inject failures
    :mixed_workload        # Combine different operations
  ]

  class << self
    # Intelligent configuration selection based on testing goals
    def for_development
      {
        thread_counts: THREAD_COUNTS.first(2),
        operations_per_thread: OPERATIONS_PER_THREAD.first(2),
        pool_sizes: POOL_SIZES.first(2),
        pool_timeouts: [POOL_TIMEOUTS.first],
        scenarios: [:mixed_workload, :rapid_fire],
        operation_mixes: [:balanced]
      }
    end

    def for_ci
      {
        thread_counts: THREAD_COUNTS.first(3),
        operations_per_thread: OPERATIONS_PER_THREAD.first(2),
        pool_sizes: POOL_SIZES.first(3),
        pool_timeouts: POOL_TIMEOUTS.first(2),
        scenarios: [:pool_starvation, :rapid_fire, :mixed_workload],
        operation_mixes: [:balanced, :read_heavy]
      }
    end

    def for_production_validation
      {
        thread_counts: THREAD_COUNTS,
        operations_per_thread: OPERATIONS_PER_THREAD,
        pool_sizes: POOL_SIZES,
        pool_timeouts: POOL_TIMEOUTS,
        scenarios: SCENARIOS,
        operation_mixes: OPERATION_MIXES.keys
      }
    end

    def for_bottleneck_analysis
      {
        thread_counts: THREAD_COUNTS.select { |t| t >= 50 },
        operations_per_thread: [1000, 5000],
        pool_sizes: POOL_SIZES.select { |p| p <= 20 },
        pool_timeouts: POOL_TIMEOUTS.select { |t| t >= 5 },
        scenarios: [:pool_starvation, :long_transactions, :error_injection],
        operation_mixes: [:transaction_heavy, :balanced]
      }
    end

    def for_performance_tuning
      {
        thread_counts: [20, 50, 100],
        operations_per_thread: [500, 1000],
        pool_sizes: [10, 20, 50],
        pool_timeouts: [5, 10, 30],
        scenarios: [:rapid_fire, :mixed_workload],
        operation_mixes: OPERATION_MIXES.keys
      }
    end

    # Runtime configuration from environment variables
    def runtime_config
      {
        thread_counts: parse_env_array('STRESS_THREADS', THREAD_COUNTS),
        operations_per_thread: parse_env_array('STRESS_OPS', OPERATIONS_PER_THREAD),
        pool_sizes: parse_env_array('STRESS_POOLS', POOL_SIZES),
        pool_timeouts: parse_env_array('STRESS_TIMEOUTS', POOL_TIMEOUTS),
        scenarios: parse_env_symbols('STRESS_SCENARIOS', SCENARIOS),
        operation_mixes: parse_env_symbols('STRESS_MIXES', OPERATION_MIXES.keys)
      }
    end

    # Configuration validation
    def validate_config(config)
      errors = []
      warnings = []

      # Thread count vs pool size validation
      if config[:thread_count] && config[:pool_size]
        if config[:thread_count] <= config[:pool_size]
          warnings << "Thread count (#{config[:thread_count]}) <= pool size (#{config[:pool_size]}) - may not create enough pressure"
        end

        if config[:thread_count] > config[:pool_size] * 10
          warnings << "Thread count (#{config[:thread_count]}) >> pool size (#{config[:pool_size]}) - may cause excessive queueing"
        end
      end

      # Operations per thread validation
      if config[:operations_per_thread]
        if config[:operations_per_thread] > 1000
          warnings << "High operation count (#{config[:operations_per_thread]}) may cause long test duration"
        end

        if config[:operations_per_thread] < 10
          warnings << "Low operation count (#{config[:operations_per_thread]}) may not provide reliable metrics"
        end
      end

      # Pool timeout validation
      if config[:pool_timeout]
        if config[:pool_timeout] < 1
          errors << "Pool timeout (#{config[:pool_timeout]}s) too low - may cause premature failures"
        end

        if config[:pool_timeout] > 60
          warnings << "Pool timeout (#{config[:pool_timeout]}s) very high - failures may take long to detect"
        end
      end

      # Scenario validation
      if config[:scenario] && !SCENARIOS.include?(config[:scenario])
        errors << "Unknown scenario: #{config[:scenario]}. Valid: #{SCENARIOS.join(', ')}"
      end

      # Operation mix validation
      if config[:operation_mix] && !OPERATION_MIXES.key?(config[:operation_mix])
        errors << "Unknown operation mix: #{config[:operation_mix]}. Valid: #{OPERATION_MIXES.keys.join(', ')}"
      end

      { errors: errors, warnings: warnings }
    end

    # Default configuration for general testing
    def default
      {
        thread_count: 20,
        operations_per_thread: 100,
        pool_size: 10,
        pool_timeout: 5,
        operation_mix: :balanced,
        scenario: :mixed_workload
      }
    end

    # Merge configurations with validation
    def merge_and_validate(*configs)
      merged = configs.reduce({}) { |acc, config| acc.merge(config) }
      validation = validate_config(merged)

      if validation[:errors].any?
        raise ArgumentError, "Configuration errors: #{validation[:errors].join('; ')}"
      end

      if validation[:warnings].any?
        puts "Configuration warnings: #{validation[:warnings].join('; ')}"
      end

      merged
    end

    private

    def parse_env_array(env_var, default)
      env_value = ENV[env_var]
      return default unless env_value

      env_value.split(',').map(&:strip).map(&:to_i)
    end

    def parse_env_symbols(env_var, default)
      env_value = ENV[env_var]
      return default unless env_value

      env_value.split(',').map(&:strip).map(&:to_sym)
    end
  end
end

# Metrics Collection
class MetricsCollector
  attr_reader :operations, :errors, :pool_stats

  def initialize
    if defined?(Concurrent)
      # Use lock-free concurrent collections
      @operations = Concurrent::Array.new
      @errors = Concurrent::Array.new
      @pool_stats = Concurrent::Array.new
      @use_concurrent = true
    else
      # Fallback to mutex-based approach
      @metrics = {
        operations: [],
        errors: [],
        wait_times: [],
        pool_stats: []
      }
      @mutex = Mutex.new
      @use_concurrent = false
    end
  end

  def record_operation(type, duration, success, wait_time = nil)
    operation_data = {
      type: type,
      duration: duration,
      success: success,
      wait_time: wait_time,
      timestamp: Time.now.to_f
    }

    if @use_concurrent
      @operations << operation_data
    else
      @mutex.synchronize do
        @metrics[:operations] << operation_data
      end
    end
  end

  def record_error(error, context = {})
    error_data = {
      error: error.class.name,
      message: error.message,
      context: context,
      timestamp: Time.now.to_f
    }

    if @use_concurrent
      @errors << error_data
    else
      @mutex.synchronize do
        @metrics[:errors] << error_data
      end
    end
  end

  def record_pool_stats(available, size)
    # Calculate utilization: if all connections are available, utilization is 0%
    # If no connections are available, utilization is 100%
    in_use = [size - available, 0].max  # Ensure non-negative
    utilization_alt = size > 0 ? (in_use.to_f / size * 100).round(2) : 0.0
    utilization = ((size - available).to_f / size * 100).round(2)
    stats_data = {
      available: available,
      size: size,
      utilization: utilization,
      utilization_alt: utilization_alt,
      in_use: in_use,
      timestamp: Time.now.to_f
    }

    if @use_concurrent
      @pool_stats << stats_data
    else
      @mutex.synchronize do
        @metrics[:pool_stats] << stats_data
      end
    end
  end

  def summary
    if @use_concurrent
      operations = @operations.to_a
      errors = @errors.to_a
      pool_stats = @pool_stats.to_a
    else
      operations = @metrics[:operations]
      errors = @metrics[:errors]
      pool_stats = @metrics[:pool_stats]
    end

    successful = operations.select { |op| op[:success] }
    failed = operations.reject { |op| op[:success] }

    {
      total_operations: operations.size,
      successful_operations: successful.size,
      failed_operations: failed.size,
      success_rate: operations.size > 0 ? (successful.size.to_f / operations.size * 100).round(2) : 0.0,
      avg_duration: operations.size > 0 ? operations.map { |op| op[:duration] }.sum.to_f / operations.size : 0.0,
      avg_wait_time: operations.size > 0 ? operations.compact.map { |op| op[:wait_time] || 0 }.sum.to_f / operations.size : 0.0,
      errors_by_type: errors.group_by { |e| e[:error] }.transform_values(&:size),
      max_pool_utilization: pool_stats.map { |s| s[:utilization] }.max || 0
    }
  end

  def to_csv
    if defined?(CSV)
      CSV.generate do |csv|
        csv << ['metric', 'value']
        summary.each do |key, value|
          csv << [key, value]
        end
      end
    else
      # Fallback to simple CSV format
      lines = ['metric,value']
      summary.each do |key, value|
        lines << "#{key},#{value}"
      end
      lines.join("\n")
    end
  end

  # Expose the legacy metrics hash interface for compatibility
  def metrics
    if @use_concurrent
      {
        operations: @operations.to_a,
        errors: @errors.to_a,
        pool_stats: @pool_stats.to_a
      }
    else
      @metrics
    end
  end
end

# Extended test models for stress testing - for now, just use BankAccount directly
# to avoid the subclass identifier issue
StressTestAccount = BankAccount

# Define helper methods on BankAccount for testing
class BankAccount
  def complex_operation
    # Simulate complex read-modify-write pattern
    refresh!
    current = balance || 0
    # sleep(0.001) # Simulate processing time
    self.balance = current + rand(-10..10)
    save
  end

  def batch_update(updates)
    updates.each do |field, value|
      send("#{field}=", value)
    end
    save
  end

  # Generate metadata of specified size
  def generate_metadata(size_class = :small)
    metadata_sizes = {
      tiny: 1,      # 1 key-value pair
      small: 10,    # 10 key-value pairs
      medium: 100,  # 100 key-value pairs
      large: 1000,  # 1000 key-value pairs
      huge: 10000   # 10000 key-value pairs
    }

    num_keys = metadata_sizes[size_class] || 10

    # Generate hash with specified number of keys
    metadata = {}
    num_keys.times do |i|
      key = "field_#{i}"
      # Create varied value types for more realistic JSON
      value = case i % 5
      when 0 then SecureRandom.hex(8)  # String
      when 1 then rand(1..1000)        # Integer
      when 2 then rand * 1000          # Float
      when 3 then [rand(1..10), rand(1..10), rand(1..10)]  # Array
      when 4 then { nested: SecureRandom.hex(4), value: rand(1..100) }  # Hash
      end
      metadata[key] = value
    end

    self.metadata = metadata
  end
end

# Stress Test Runner
class ConnectionPoolStressTest
  attr_reader :config, :metrics

  def initialize(config = {})
    @config = {
      thread_count: 10,
      operations_per_thread: 100,
      pool_size: 10,
      pool_timeout: 5,
      operation_mix: :balanced,
      scenario: :mixed_workload,
      shared_accounts: nil, # nil means one account per thread (original behavior)
      fresh_records: false, # false means reuse accounts, true means create new each operation
      duration: nil, # nil means operations-based, otherwise time-based in seconds
      workload_size: :small, # Size of metadata: tiny, small, medium, large, huge
      profile_id_generation: false, # if true, pre-generate account IDs
    }.merge(config)

    @metrics = MetricsCollector.new
    @shared_accounts = [] # Will hold shared account instances
    @pre_generated_ids = [] # For ID generation profiling
    setup_connection_pool
    setup_shared_accounts if @config[:shared_accounts]
    setup_pre_generated_ids if @config[:profile_id_generation]
  end

  def setup_connection_pool
    # Reconfigure connection pool with test parameters
    pool_size = @config[:pool_size]
    pool_timeout = @config[:pool_timeout]

    # Use class_variable_set to properly set the class variable
    Familia.class_variable_set(:@@connection_pool, ConnectionPool.new(
      size: pool_size,
      timeout: pool_timeout
    ) do
      Redis.new(url: Familia.uri.to_s)
    end)

    # Verify the pool was configured correctly
    actual_size = Familia.connection_pool.size
    if actual_size != pool_size
      puts "WARNING: Pool size mismatch! Configured: #{pool_size}, Actual: #{actual_size}"
    end
  end

  def setup_shared_accounts
    # Create a limited set of accounts that all threads will contend over
    @config[:shared_accounts].times do |i|
      account = StressTestAccount.new
      account.balance = 1000
      account.holder_name = "SharedAccount#{i}"
      account.generate_metadata(@config[:workload_size])
      account.save
      @shared_accounts << account
    end
    puts "Created #{@shared_accounts.size} shared accounts for high-contention testing"
  end

  def setup_pre_generated_ids
    # Pre-generate account IDs to test if SecureRandom is a bottleneck
    total_needed = if @config[:duration]
      # Estimate based on typical throughput
      @config[:thread_count] * 100  # Assume ~100 ops/thread/sec as starting point
    else
      @config[:thread_count] * @config[:operations_per_thread]
    end

    puts "Pre-generating #{total_needed} account IDs for profiling..."
    total_needed.times do
      @pre_generated_ids << SecureRandom.hex(8)
    end
    @id_index = 0
    @id_mutex = Mutex.new
    puts "ID pre-generation complete"
  end

  def get_next_pre_generated_id
    @id_mutex.synchronize do
      id = @pre_generated_ids[@id_index % @pre_generated_ids.length]
      @id_index += 1
      id
    end
  end

  def get_account_for_thread(thread_index)
    if @config[:shared_accounts]
      # Return one of the shared accounts (round-robin distribution)
      @shared_accounts[thread_index % @shared_accounts.size]
    else
      # Original behavior: create unique account per thread
      account = StressTestAccount.new
      account.balance = 1000
      account.holder_name = "Thread#{thread_index}"
      account.generate_metadata(@config[:workload_size])
      account.save
      account
    end
  end

  def get_account_for_operation(thread_index, operation_index)
    if @config[:fresh_records]
      # Create a new account for every operation
      account = StressTestAccount.new
      if @config[:profile_id_generation]
        # Use pre-generated ID
        account.instance_variable_set(:@account_number, get_next_pre_generated_id)
      end
      account.balance = 1000
      account.holder_name = "T#{thread_index}_Op#{operation_index}"
      account.generate_metadata(@config[:workload_size])
      account.save
      account
    else
      # Use the existing account for this thread
      get_account_for_thread(thread_index)
    end
  end

  def run
    puts "\n=== Starting Stress Test ==="
    puts "Configuration: #{@config.inspect}"

    case @config[:scenario]
    when :pool_starvation
      run_pool_starvation_test
    when :rapid_fire
      run_rapid_fire_test
    when :long_transactions
      run_long_transactions_test
    when :nested_transactions
      run_nested_transactions_test
    when :error_injection
      run_error_injection_test
    else
      run_mixed_workload_test
    end

    puts "\n=== Test Complete ==="
    display_summary
  end

  private

  def run_pool_starvation_test
    # Create more threads than pool connections
    thread_count = @config[:pool_size] * 2
    threads = []

    puts "Running pool starvation test with #{thread_count} threads and pool size #{@config[:pool_size]}"

    thread_count.times do |i|
      threads << Thread.new do
        begin
          @config[:operations_per_thread].times do |op_index|
            account = get_account_for_operation(i, op_index)
            begin
              start = Time.now
              wait_start = Time.now

              Familia.atomic do
                wait_time = Time.now - wait_start
                account.complex_operation
                @metrics.record_operation(:transaction, Time.now - start, true, wait_time)
              end
            rescue => e
              @metrics.record_error(e, { thread: i })
              @metrics.record_operation(:transaction, Time.now - start, false)
            end
          end
        rescue => e
          puts "Thread #{i} setup error: #{e.message} (#{e.class})" if ENV['FAMILIA_DEBUG']
          @metrics.record_error(e, { thread: i, phase: :setup })
        end
      end
    end

    # Monitor pool utilization
    monitor_thread = Thread.new do
      begin
        while threads.any?(&:alive?)
          if Familia.connection_pool.respond_to?(:available)
            @metrics.record_pool_stats(
              Familia.connection_pool.available,
              Familia.connection_pool.size
            )
          end
          sleep 0.01  # Poll every 10ms for finer granularity
        end
      rescue => e
        puts "Monitor thread error: #{e.message}" if ENV['FAMILIA_DEBUG']
      end
    end

    threads.each(&:join)
    monitor_thread.kill if monitor_thread.alive?
  end

  def run_rapid_fire_test
    threads = []

    puts "Running rapid fire test with #{@config[:thread_count]} threads"

    if @config[:duration]
      end_time = Time.now + @config[:duration]

      @config[:thread_count].times do |i|
        threads << Thread.new do
          op_index = 0
          while Time.now < end_time
            account = get_account_for_operation(i, op_index)
            operation = select_operation
            execute_operation(account, operation)
            op_index += 1
          end
        end
      end
    else
      @config[:thread_count].times do |i|
        threads << Thread.new do
          @config[:operations_per_thread].times do |op_index|
            account = get_account_for_operation(i, op_index)
            operation = select_operation
            execute_operation(account, operation)
          end
        end
      end
    end

    # Monitor pool utilization
    monitor_thread = Thread.new do
      begin
        while threads.any?(&:alive?)
          if Familia.connection_pool.respond_to?(:available)
            @metrics.record_pool_stats(
              Familia.connection_pool.available,
              Familia.connection_pool.size
            )
          end
          sleep 0.01  # Poll every 10ms for finer granularity
        end
      rescue => e
        puts "Monitor thread error: #{e.message}" if ENV['FAMILIA_DEBUG']
      end
    end

    threads.each(&:join)
    monitor_thread.kill if monitor_thread.alive?
  end

  def run_long_transactions_test
    threads = []

    puts "Running long transactions test"

    @config[:thread_count].times do |i|
      threads << Thread.new do
        account1 = StressTestAccount.new
        account1.balance = 1000
        account1.holder_name = "Long1_#{i}"
        account2 = StressTestAccount.new
        account2.balance = 1000
        account2.holder_name = "Long2_#{i}"

        @config[:operations_per_thread].times do
          begin
            start = Time.now

            Familia.atomic do
              # Simulate long-running transaction
              account1.refresh!
              account2.refresh!
              # sleep(0.1) # Hold connection longer

              account1.withdraw(100)
              account2.deposit(100)

              account1.save
              account2.save
            end

            @metrics.record_operation(:long_transaction, Time.now - start, true)
          rescue => e
            @metrics.record_error(e, { thread: i })
            @metrics.record_operation(:long_transaction, Time.now - start, false)
          end
        end
      end
    end

    threads.each(&:join)
  end

  def run_nested_transactions_test
    threads = []

    puts "Running nested transactions test"

    @config[:thread_count].times do |i|
      threads << Thread.new do
        account = StressTestAccount.new
        account.balance = 1000
        account.holder_name = "Nested#{i}"

        @config[:operations_per_thread].times do
          begin
            start = Time.now

            Familia.atomic do
              account.deposit(50)
              account.save

              # Nested transaction (should be separate)
              Familia.atomic do
                account.deposit(25)
                account.save
              end

              account.withdraw(10)
              account.save
            end

            @metrics.record_operation(:nested_transaction, Time.now - start, true)
          rescue => e
            @metrics.record_error(e, { thread: i })
            @metrics.record_operation(:nested_transaction, Time.now - start, false)
          end
        end
      end
    end

    threads.each(&:join)
  end

  def run_error_injection_test
    threads = []
    error_rate = 0.1 # 10% error rate

    puts "Running error injection test with #{(error_rate * 100).to_i}% error rate"

    @config[:thread_count].times do |i|
      threads << Thread.new do
        account = StressTestAccount.new
        account.balance = 1000
        account.holder_name = "Error#{i}"

        @config[:operations_per_thread].times do |op_num|
          begin
            start = Time.now

            if rand < error_rate
              # Inject an error
              raise "Simulated error in thread #{i}, operation #{op_num}"
            end

            Familia.atomic do
              account.complex_operation
            end

            @metrics.record_operation(:with_errors, Time.now - start, true)
          rescue => e
            @metrics.record_error(e, { thread: i, operation: op_num })
            @metrics.record_operation(:with_errors, Time.now - start, false)
          end
        end
      end
    end

    threads.each(&:join)
  end

  def run_mixed_workload_test
    threads = []
    mix = StressTestConfig::OPERATION_MIXES[@config[:operation_mix]]

    puts "Running mixed workload test with mix: #{mix.inspect}"

    if @config[:duration]
      run_duration_based_test(mix)
    else
      run_operations_based_test(mix)
    end
  end

  def run_duration_based_test(mix)
    threads = []
    end_time = Time.now + @config[:duration]

    @config[:thread_count].times do |i|
      threads << Thread.new do
        op_index = 0
        while Time.now < end_time
          account = get_account_for_operation(i, op_index)
          operation = select_operation_from_mix(mix)
          execute_operation(account, operation)
          op_index += 1
        end
      end
    end

    # Monitor pool utilization
    monitor_thread = Thread.new do
      begin
        while threads.any?(&:alive?)
          if Familia.connection_pool.respond_to?(:available)
            @metrics.record_pool_stats(
              Familia.connection_pool.available,
              Familia.connection_pool.size
            )
          end
          sleep 0.001  # Poll every 1ms for better granularity with fast operations
        end
      rescue => e
        puts "Monitor thread error: #{e.message}" if ENV['FAMILIA_DEBUG']
      end
    end

    threads.each(&:join)
    monitor_thread.kill if monitor_thread.alive?
  end

  def run_operations_based_test(mix)
    threads = []

    @config[:thread_count].times do |i|
      threads << Thread.new do
        @config[:operations_per_thread].times do |op_index|
          account = get_account_for_operation(i, op_index)
          operation = select_operation_from_mix(mix)
          execute_operation(account, operation)
        end
      end
    end

    # Monitor pool utilization
    monitor_thread = Thread.new do
      begin
        while threads.any?(&:alive?)
          if Familia.connection_pool.respond_to?(:available)
            @metrics.record_pool_stats(
              Familia.connection_pool.available,
              Familia.connection_pool.size
            )
          end
          sleep 0.001  # Poll every 1ms for better granularity with fast operations
        end
      rescue => e
        puts "Monitor thread error: #{e.message}" if ENV['FAMILIA_DEBUG']
      end
    end

    threads.each(&:join)
    monitor_thread.kill if monitor_thread.alive?
  end

  def select_operation
    [:read, :write, :transaction].sample
  end

  def select_operation_from_mix(mix)
    rand_num = rand(100)
    cumulative = 0

    mix.each do |op, percentage|
      cumulative += percentage
      return op if rand_num < cumulative
    end

    :read # fallback
  end

  def execute_operation(account, operation)
    begin
      start = Time.now

      case operation
      when :read
        account.refresh!
        _ = account.balance
        @metrics.record_operation(:read, Time.now - start, true)
      when :write
        current = account.balance || 0
        account.balance = current + rand(-10..10)
        account.save
        @metrics.record_operation(:write, Time.now - start, true)
      when :transaction
        Familia.atomic do
          account.refresh!
          current = account.balance || 0
          account.balance = current + rand(-10..10)
          account.save
        end
        @metrics.record_operation(:transaction, Time.now - start, true)
      end
    rescue => e
      puts "Operation error: #{e.message} (#{e.class})" if ENV['FAMILIA_DEBUG']
      @metrics.record_error(e, { operation: operation })
      @metrics.record_operation(operation, Time.now - start, false)
    end
  end

  def display_summary
    summary = @metrics.summary

    puts "\n=== Summary ==="
    summary.each do |key, value|
      puts "#{key}: #{value}"
    end
  end
end

# Run basic test if executed directly
if __FILE__ == $0
  Familia.debug = false
  BankAccount.redis.flushdb

  # Run a simple test
  test = ConnectionPoolStressTest.new(
    thread_count: 20,
    operations_per_thread: 50,
    pool_size: 10,
    pool_timeout: 5,
    operation_mix: :balanced,
    scenario: :pool_starvation
  )

  test.run

  # Output CSV
  puts "\n=== CSV Output ==="
  puts test.metrics.to_csv
end
