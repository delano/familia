# try/pooling/lib/connection_pool_threading_models.rb
#
# Different Threading Models for Connection Pool Stress Testing
#
# This module provides various concurrency models to test the connection pool:
# 1. Traditional Threads - Ruby's Thread class
# 2. Fiber-based concurrency - Using Fibers (with or without scheduler)
# 3. Thread Pool Pattern - Fixed pool of worker threads
# 4. Actor Model - Message-passing concurrency (simplified)

require 'fiber'
require 'thread'
require_relative 'connection_pool_stress_test'

module ThreadingModels
  # Base class for all threading models
  class BaseModel
    attr_reader :metrics, :config

    def initialize(config, metrics)
      @config = config
      @metrics = metrics
      @operations_queue = Queue.new if respond_to?(:uses_queue?) && uses_queue?
    end

    def run(&block)
      raise NotImplementedError, "Subclasses must implement #run"
    end

    protected

    def create_test_account(identifier)
      account = StressTestAccount.new
      account.balance = 1000
      account.holder_name = "#{self.class.name.split('::').last}_#{identifier}"
      account
    end
  end

  # Traditional Ruby Threads
  class TraditionalThreads < BaseModel
    def run(&block)
      threads = []

      @config[:thread_count].times do |i|
        threads << Thread.new(i) do |thread_id|
          account = create_test_account(thread_id)
          account.save

          @config[:operations_per_thread].times do |op_num|
            yield(account, thread_id, op_num)
          end
        end
      end

      threads.each(&:join)

      {
        model: 'TraditionalThreads',
        thread_count: threads.size,
        all_completed: threads.all? { |t| !t.alive? }
      }
    end
  end

  # Fiber-based concurrency (cooperative)
  class FiberBased < BaseModel
    def run(&block)
      fibers = []
      completed = 0

      # Create fibers
      @config[:thread_count].times do |i|
        fibers << Fiber.new do
          account = create_test_account(i)
          account.save

          @config[:operations_per_thread].times do |op_num|
            yield(account, i, op_num)
            Fiber.yield # Cooperative yield
          end

          completed += 1
        end
      end

      # Run fibers in round-robin fashion
      while fibers.any? { |f| f.alive? }
        fibers.each do |fiber|
          fiber.resume if fiber.alive?
        end
      end

      {
        model: 'FiberBased',
        fiber_count: fibers.size,
        completed: completed
      }
    end
  end

  # Thread Pool Pattern
  class ThreadPool < BaseModel
    def uses_queue?
      true
    end

    def run(&block)
      pool_size = @config[:worker_pool_size] || 10
      workers = []
      work_items = Queue.new
      completed = Concurrent::AtomicFixnum.new(0) rescue completed = 0

      # Populate work queue
      @config[:thread_count].times do |i|
        @config[:operations_per_thread].times do |op_num|
          work_items << [i, op_num]
        end
      end

      # Create worker threads
      pool_size.times do |worker_id|
        workers << Thread.new do
          loop do
            begin
              work = work_items.pop(true) # non-blocking pop
              account_id, op_num = work

              account = create_test_account("#{worker_id}_#{account_id}")
              yield(account, account_id, op_num)

              if defined?(Concurrent) && completed.respond_to?(:increment)
                completed.increment
              elsif completed.is_a?(Numeric)
                completed += 1
              end
            rescue ThreadError
              # Queue is empty
              break
            end
          end
        end
      end

      workers.each(&:join)

      {
        model: 'ThreadPool',
        pool_size: pool_size,
        total_operations: @config[:thread_count] * @config[:operations_per_thread],
        completed: defined?(Concurrent) ? completed.value : 'N/A'
      }
    end
  end

  # Hybrid: Threads with Fiber-based operations
  class HybridThreadFiber < BaseModel
    def run(&block)
      threads = []

      @config[:thread_count].times do |thread_id|
        threads << Thread.new do
          # Each thread runs multiple fibers
          fibers = []
          fibers_per_thread = [@config[:operations_per_thread] / 10, 1].max
          ops_per_fiber = @config[:operations_per_thread] / fibers_per_thread

          fibers_per_thread.times do |fiber_id|
            fibers << Fiber.new do
              account = create_test_account("#{thread_id}_#{fiber_id}")
              account.save

              ops_per_fiber.times do |op_num|
                yield(account, thread_id, op_num)
                Fiber.yield
              end
            end
          end

          # Run fibers within thread
          while fibers.any? { |f| f.alive? }
            fibers.each { |f| f.resume if f.alive? }
          end
        end
      end

      threads.each(&:join)

      {
        model: 'HybridThreadFiber',
        thread_count: threads.size,
        fibers_per_thread: @config[:operations_per_thread] / 10
      }
    end
  end

  # Actor Model (simplified)
  class ActorModel < BaseModel
    class Actor
      def initialize(id, metrics)
        @id = id
        @metrics = metrics
        @mailbox = Queue.new
        @thread = Thread.new { process_messages }
      end

      def send_message(message)
        @mailbox << message
      end

      def stop
        @mailbox << :stop
        @thread.join
      end

      private

      def process_messages
        loop do
          message = @mailbox.pop
          break if message == :stop

          operation, account, callback = message
          result = perform_operation(operation, account)
          callback.call(result) if callback
        end
      end

      def perform_operation(operation, account)
        start = Familia.now

        case operation[:type]
        when :read
          account.refresh!
          { success: true, duration: Familia.now - start }
        when :write
          account.balance += operation[:amount] || 0
          account.save
          { success: true, duration: Familia.now - start }
        when :transaction
          Familia.atomic do
            account.complex_operation
          end
          { success: true, duration: Familia.now - start }
        end
      rescue => e
        { success: false, error: e, duration: Familia.now - start }
      end
    end

    def run(&block)
      actors = []
      results = Queue.new

      # Create actors
      actor_count = [@config[:thread_count] / 2, 1].max
      actor_count.times do |i|
        actors << Actor.new(i, @metrics)
      end

      # Distribute work among actors
      @config[:thread_count].times do |i|
        account = create_test_account(i)
        account.save

        @config[:operations_per_thread].times do |op_num|
          actor = actors[i % actors.size]

          actor.send_message([
            { type: [:read, :write, :transaction].sample },
            account,
            ->(result) { results << result }
          ])
        end
      end

      # Wait for all operations to complete
      expected_ops = @config[:thread_count] * @config[:operations_per_thread]
      received = 0

      while received < expected_ops
        result = results.pop
        received += 1

        @metrics.record_operation(
          result[:type] || :unknown,
          result[:duration],
          result[:success]
        )
      end

      # Stop actors
      actors.each(&:stop)

      {
        model: 'ActorModel',
        actor_count: actors.size,
        operations_completed: received
      }
    end
  end

  # Factory method to create threading model
  def self.create(model_name, config, metrics)
    case model_name
    when :traditional
      TraditionalThreads.new(config, metrics)
    when :fiber
      FiberBased.new(config, metrics)
    when :thread_pool
      ThreadPool.new(config, metrics)
    when :hybrid
      HybridThreadFiber.new(config, metrics)
    when :actor
      ActorModel.new(config, metrics)
    else
      raise ArgumentError, "Unknown threading model: #{model_name}"
    end
  end
end

# Enhanced stress test with threading models
class EnhancedConnectionPoolStressTest < ConnectionPoolStressTest
  THREADING_MODELS = [:traditional, :fiber, :thread_pool, :hybrid, :actor]

  def initialize(config = {})
    super
    @threading_model = config[:threading_model] || :traditional
  end

  def run_with_model(model_name = nil)
    model_name ||= @threading_model
    model = ThreadingModels.create(model_name, @config, @metrics)

    puts "\n=== Running with #{model_name} model ==="

    start_time = Familia.now

    result = model.run do |account, thread_id, op_num|
      operation = select_operation_from_mix(
        StressTestConfig::OPERATION_MIXES[@config[:operation_mix]]
      )
      execute_operation(account, operation)
    end

    duration = Familia.now - start_time

    result.merge(
      total_duration: duration,
      operations_per_second: (@config[:thread_count] * @config[:operations_per_thread]) / duration
    )
  end

  def compare_all_models
    results = {}

    THREADING_MODELS.each do |model|
      @metrics = MetricsCollector.new # Fresh metrics for each model
      results[model] = run_with_model(model)
      results[model][:summary] = @metrics.summary
    end

    display_comparison(results)
    results
  end

  private

  def display_comparison(results)
    puts "\n=== Threading Model Comparison ==="
    puts sprintf("%-15s %-10s %-10s %-10s %-10s %-10s",
                 "Model", "Duration", "Ops/Sec", "Success%", "Errors", "Max Pool%")
    puts "-" * 75

    results.each do |model, data|
      summary = data[:summary]
      puts sprintf("%-15s %-10.2f %-10.2f %-10.2f %-10d %-10.2f",
                   model,
                   data[:total_duration],
                   data[:operations_per_second],
                   summary[:success_rate],
                   summary[:failed_operations],
                   summary[:max_pool_utilization])
    end
  end
end

# Run comparison if executed directly
if __FILE__ == $0
  Familia.debug = false
  BankAccount.dbclient.flushdb

  test = EnhancedConnectionPoolStressTest.new(
    thread_count: 20,
    operations_per_thread: 50,
    pool_size: 10,
    pool_timeout: 5,
    operation_mix: :balanced,
    scenario: :mixed_workload,
    worker_pool_size: 8
  )

  results = test.compare_all_models

  # Output results as CSV
  puts "\n=== CSV Output for Import ==="
  CSV do |csv|
    csv << ['model', 'duration', 'ops_per_sec', 'success_rate', 'failed_ops', 'max_pool_util']
    results.each do |model, data|
      summary = data[:summary]
      csv << [
        model,
        data[:total_duration],
        data[:operations_per_second],
        summary[:success_rate],
        summary[:failed_operations],
        summary[:max_pool_utilization]
      ]
    end
  end
end
