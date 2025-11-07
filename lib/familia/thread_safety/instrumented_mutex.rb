# lib/familia/thread_safety/instrumented_mutex.rb
#
# frozen_string_literal: true

require_relative 'monitor'

module Familia
  module ThreadSafety
    # A Mutex wrapper that automatically reports contention metrics
    #
    # This class wraps Ruby's standard Mutex to provide automatic
    # instrumentation of lock contention and wait times.
    #
    # @example Basic usage
    #   mutex = Familia::ThreadSafety::InstrumentedMutex.new('connection_chain')
    #   mutex.synchronize { # critical section }
    #
    # @example With monitoring
    #   Familia::ThreadSafety::Monitor.start!
    #   mutex = Familia::ThreadSafety::InstrumentedMutex.new('field_registration')
    #   mutex.synchronize { # automatically tracked }
    class InstrumentedMutex
      attr_reader :name, :mutex

      # Create a new instrumented mutex
      #
      # @param name [String, Symbol] Identifier for this mutex in monitoring
      # @param monitor [Monitor, nil] Monitor instance to use (defaults to singleton)
      def initialize(name, monitor = nil)
        @name = name.to_s
        @mutex = ::Mutex.new
        @monitor = monitor || Monitor.instance
        @lock_count = Concurrent::AtomicFixnum.new(0)
        @contention_count = Concurrent::AtomicFixnum.new(0)
      end

      # Synchronize with automatic monitoring
      #
      # @yield Block to execute while holding the lock
      # @return Result of the block
      def synchronize
        return yield unless @monitor.enabled

        acquired = false
        wait_start = Familia.now_in_μs

        # Try non-blocking acquisition first to detect contention
        if @mutex.try_lock
          acquired = true
          wait_time = 0
          @lock_count.increment
        else
          # Contention detected
          @contention_count.increment
          @monitor.record_contention(@name)

          # Now do blocking acquisition
          @mutex.lock
          acquired = true
          wait_end = Familia.now_in_μs
          wait_time_μs = wait_end - wait_start

          @lock_count.increment
          @monitor.record_wait_time(@name, wait_time_μs)

          if wait_time_μs > 10_000  # Log if waited more than 10ms (10,000μs)
            Familia.trace(:MUTEX_WAIT, nil, "Waited #{(wait_time_μs / 1000.0).round(2)}ms for #{@name}")
          end
        end

        yield
      ensure
        @mutex.unlock if acquired
      end

      # Acquire the lock (with monitoring)
      def lock
        return @mutex.lock unless @monitor.enabled

        wait_start = Familia.now_in_μs

        if @mutex.try_lock
          @lock_count.increment
          return true
        end

        # Contention detected
        @contention_count.increment
        @monitor.record_contention(@name)

        result = @mutex.lock
        wait_end = Familia.now_in_μs
        wait_time_μs = wait_end - wait_start

        @lock_count.increment
        @monitor.record_wait_time(@name, wait_time_μs)

        result
      end

      # Try to acquire the lock without blocking
      def try_lock
        result = @mutex.try_lock
        @lock_count.increment if result
        result
      end

      # Release the lock
      def unlock
        @mutex.unlock
      end

      # Check if locked by current thread
      def locked?
        @mutex.locked?
      end

      # Check if owned by current thread
      def owned?
        @mutex.owned?
      end

      # Sleep and release the lock temporarily
      def sleep(timeout = nil)
        @mutex.sleep(timeout)
      end

      # Get statistics for this mutex
      def stats
        {
          name: @name,
          lock_count: @lock_count.value,
          contention_count: @contention_count.value,
          contention_rate: contention_rate
        }
      end

      # Calculate contention rate (0.0 to 1.0)
      def contention_rate
        total = @lock_count.value
        return 0.0 if total == 0

        @contention_count.value.to_f / total
      end

      # Create a double-checked locking helper
      #
      # @param check [Proc] Condition to check
      # @param init [Proc] Initialization to perform if check fails
      # @return Result of check or init
      def double_checked_locking(check, init)
        # Fast path - check without lock
        value = check.call
        return value if value

        # Slow path - check again with lock
        synchronize do
          value = check.call
          return value if value

          init.call
        end
      end
    end
  end
end
