# lib/middleware/database_logger.rb
#
# frozen_string_literal: true

require 'concurrent-ruby'

# DatabaseLogger is redis-rb middleware for command logging and capture.
#
# Provides detailed Redis command logging for development and debugging.
# Familia uses the redis-rb gem (v4.8.1 to <6.0), which internally uses
# RedisClient infrastructure for middleware. Users work with Redis.new
# connections and Redis:: exceptions - RedisClient is an implementation detail.
#
# ## User-Facing API
#
# Enable via Familia configuration:
#   Familia.enable_database_logging = true
#
# Familia automatically calls RedisClient.register(DatabaseLogger) internally.
#
# ## Critical: Uses `super` not `yield` for middleware chaining
# @see https://github.com/redis-rb/redis-client#instrumentation-and-middlewares
# ## Internal: RedisClient Middleware Architecture
#
# RedisClient middlewares are modules that are `include`d into the
# `RedisClient::Middlewares` class, which inherits from `BasicMiddleware`.
# The middleware chain works through Ruby's method lookup and `super`.
#
# ### Middleware Chain Flow (Internal)
#
# ```ruby
# # Internal registration order (last registered is called first):
# RedisClient.register(DatabaseLogger)         # Called second (internal)
# RedisClient.register(DatabaseCommandCounter)  # Called first (internal)
#
# # Execution flow when client.call('SET', 'key', 'value') is invoked:
# DatabaseCommandCounter.call(cmd, config) { |result| ... }
#   └─> super  # Implicitly passes block to next middleware
#       └─> DatabaseLogger.call(cmd, config)
#           └─> super  # Implicitly passes block to next middleware
#               └─> BasicMiddleware.call(cmd, config)
#                   └─> yield command  # Executes actual Redis command
#                       └─> Returns result
#                   ← result flows back up
#               ← result flows back up
#           ← result flows back up
#       ← result flows back up
# ```
#
# ### Critical Implementation Detail: `super` vs `yield`
#
# **MUST use `super`** to properly chain middlewares. Using `yield` breaks
# the chain because it executes the original block directly, bypassing other
# middlewares in the chain.
#
# ```ruby
# # ✅ CORRECT - Chains to next middleware
# def call(command, config)
#   result = super  # Calls next middleware, block passes implicitly
#   result
# end
#
# # ❌ WRONG - Breaks middleware chain
# def call(command, config)
#   result = yield  # Executes block directly, skips other middlewares!
#   result
# end
# ```
#
# When `super` is called:
# 1. Ruby automatically passes the block to the next method in the chain
# 2. The next middleware's `call` method executes
# 3. Eventually reaches `BasicMiddleware.call` which does `yield command`
# 4. The actual Redis command executes
# 5. Results flow back up through each middleware
#
# ## Usage Examples
#
# @example Enable Redis command logging (recommended user-facing API)
#   Familia.enable_database_logging = true
#
# @example Capture commands for testing
#   commands = DatabaseLogger.capture_commands do
#     redis.set('key', 'value')
#     redis.get('key')
#   end
#   puts commands.first.command  # => "SET key value"
#
# @example Use with DatabaseCommandCounter
#   Familia.enable_database_logging = true
#   Familia.enable_database_counter = true
#   # Both middlewares registered automatically and execute correctly in sequence
#
# rubocop:disable ThreadSafety/ClassInstanceVariable
module DatabaseLogger
  # Data structure for captured command metadata
  CommandMessage = Data.define(:command, :μs, :timeline) do
    alias_method :to_a, :deconstruct

    def inspect
      cmd, duration, timeline = to_a
      format('%.6f %4dμs > %s', timeline, duration, cmd)
    end
  end

  @logger = nil
  @commands = Concurrent::Array.new
  @max_commands = 10_000
  @process_start = Time.now.to_f.freeze
  @structured_logging = false
  @sample_rate = nil  # nil = log everything, 0.1 = 10%, 0.01 = 1%
  @sample_counter = Concurrent::AtomicFixnum.new(0)
  @commands_mutex = Mutex.new  # Protects compound operations on @commands

  class << self
    # Gets/sets the logger instance used by DatabaseLogger.
    # @return [Logger, nil] The current logger instance or nil if not set.
    attr_accessor :logger

    # Gets/sets the maximum number of commands to capture.
    # @return [Integer] The maximum number of commands to capture.
    attr_accessor :max_commands

    # Gets/sets structured logging mode.
    # When enabled, outputs Redis commands with structured key=value context
    # instead of formatted string output.
    #
    # @return [Boolean] Whether structured logging is enabled
    #
    # @example Enable structured logging
    #   DatabaseLogger.structured_logging = true
    #   # Outputs: "Redis command cmd=SET args=[key, value] duration_ms=0.42 db=0"
    #
    # @example Disable (default formatted output)
    #   DatabaseLogger.structured_logging = false
    #   # Outputs: "[123] 0.001234 567μs > SET key value"
    attr_accessor :structured_logging

    # Gets/sets the sampling rate for logging.
    # Controls what percentage of commands are logged to reduce noise.
    #
    # @return [Float, nil] Sample rate (0.0-1.0) or nil for no sampling
    #
    # @example Log 10% of commands
    #   DatabaseLogger.sample_rate = 0.1
    #
    # @example Log 1% of commands (high-traffic production)
    #   DatabaseLogger.sample_rate = 0.01
    #
    # @example Disable sampling (log everything)
    #   DatabaseLogger.sample_rate = nil
    #
    # @note Command capture is unaffected - only logger output is sampled.
    #   This means tests can still verify commands while production logs stay clean.
    attr_accessor :sample_rate

    # Gets the captured commands for testing purposes.
    # @return [Array<CommandMessage>] Array of captured command messages
    attr_reader :commands

    # Gets the timestamp when DatabaseLogger was loaded.
    # @return [Float] The timestamp when DatabaseLogger was loaded.
    attr_reader :process_start

    # Clears the captured commands array.
    #
    # Thread-safe via mutex to ensure test isolation.
    #
    # @return [nil]
    def clear_commands
      @commands_mutex.synchronize do
        @commands.clear
      end
      nil
    end

    # Captures commands in a block and returns them.
    # This is useful for testing to see what commands were executed.
    #
    # @yield [] The block of code to execute while capturing commands.
    # @return [Array<CommandMessage>] Array of captured command messages
    #
    # @example Test what Redis commands your code executes
    #   commands = DatabaseLogger.capture_commands do
    #     my_library_method()
    #   end
    #   assert_equal "SET", commands.first.command.split.first
    #   assert commands.first.μs > 0
    def capture_commands
      clear_commands
      yield
      @commands.to_a
    end

    # Gets the current count of captured commands.
    # @return [Integer] The number of commands currently captured
    def index
      @commands.size
    end

    # Appends a command message to the captured commands array.
    #
    # When the array reaches max_commands capacity, the oldest command is
    # removed before adding the new one.
    #
    # @param message [CommandMessage] The command message to append
    # @return [Array<CommandMessage>] The updated array of commands
    # @api private
    def append_command(message)
      # We can throw away commands and not worry about thread race conditions
      # since no one is going to mind if the command list is +/- a few
      # commands. Unlike how we care about the order that the commands
      # appear in the list, we don't care about exact count when trimming.
      @commands.shift if @commands.size >= @max_commands
      @commands << message # this is threadsafe thanks to Concurrent::Array
    end

    # Returns the current time in microseconds.
    # This is used to measure the duration of Redis commands.
    #
    # @return [Integer] The current time in microseconds
    def now_in_μs
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
    end
    alias now_in_microseconds now_in_μs

    # Determines if this command should be logged based on sampling rate.
    #
    # Uses deterministic modulo-based sampling for consistent behavior.
    # Thread-safe via atomic counter increment.
    #
    # @return [Boolean] true if command should be logged
    # @api private
    def should_log?
      return true if @sample_rate.nil?
      return false if @logger.nil?

      # Deterministic sampling: every Nth command where N = 1/sample_rate
      # e.g., 0.1 = every 10th, 0.01 = every 100th
      sample_interval = (1.0 / @sample_rate).to_i
      (@sample_counter.increment % sample_interval).zero?
    end
  end

  # Logs the Redis command and its execution time.
  #
  # This method is part of the RedisClient middleware chain. It MUST use `super`
  # instead of `yield` to properly chain with other middlewares.
  #
  # @param command [Array] The Redis command and its arguments
  # @param config [RedisClient::Config, Hash] Connection configuration
  # @return [Object] The result of the Redis command execution
  #
  # @note Commands are always captured for testing. Logging only occurs when
  #   DatabaseLogger.logger is set and sampling allows it.
  def call(command, config)
    block_start = DatabaseLogger.now_in_μs
    result = super  # CRITICAL: Must use super, not yield, to chain middlewares
    block_duration = DatabaseLogger.now_in_μs - block_start

    # We intentionally use two different codepaths for getting the
    # time, although they will almost always be so similar that the
    # difference is negligible.
    lifetime_duration = (Time.now.to_f - DatabaseLogger.process_start).round(6)

    msgpack = CommandMessage.new(command.join(' '), block_duration, lifetime_duration)
    DatabaseLogger.append_command(msgpack)

    # Dual-mode logging with sampling
    if DatabaseLogger.should_log?
      if DatabaseLogger.structured_logging && DatabaseLogger.logger
        duration_ms = (block_duration / 1000.0).round(2)
        db_num = if config.respond_to?(:db)
                   config.db
                 elsif config.is_a?(Hash)
                   config[:db]
                 end
        DatabaseLogger.logger.trace(
          "Redis command cmd=#{command.first} args=#{command[1..-1].inspect} " \
          "duration_μs=#{block_duration} duration_ms=#{duration_ms} " \
          "timeline=#{lifetime_duration} db=#{db_num} index=#{DatabaseLogger.index}"
        )
      elsif DatabaseLogger.logger
        # Existing formatted output
        message = format('[%s] %s', DatabaseLogger.index, msgpack.inspect)
        DatabaseLogger.logger.trace(message)
      end
    end

    # Notify instrumentation hooks
    if defined?(Familia::Instrumentation)
      duration_ms = (block_duration / 1000.0).round(2)
      db_num = if config.respond_to?(:db)
                   config.db
                 elsif config.is_a?(Hash)
                   config[:db]
                 end
      conn_id = if config.respond_to?(:custom)
                   config.custom&.dig(:id)
                 elsif config.is_a?(Hash)
                   config.dig(:custom, :id)
                 end
      Familia::Instrumentation.notify_command(
        command.first,
        duration_ms,
        full_command: command,
        db: db_num,
        connection_id: conn_id,
      )
    end

    result
  end

  # Handle pipelined commands (including MULTI/EXEC transactions)
  #
  # Captures MULTI/EXEC and shows you the full transaction. The WATCH
  # and EXISTS appear separately because they're executed as individual
  # commands before the transaction starts.
  #
  # @param commands [Array<Array>] Array of command arrays
  # @param config [RedisClient::Config, Hash] Connection configuration
  # @return [Array] Results from pipelined commands
  def call_pipelined(commands, config)
    block_start = DatabaseLogger.now_in_μs
    results = yield  # CRITICAL: For call_pipelined, yield is correct (not chaining)
    block_duration = DatabaseLogger.now_in_μs - block_start
    lifetime_duration = (Time.now.to_f - DatabaseLogger.process_start).round(6)

    # Log the entire pipeline as a single operation
    cmd_string = commands.map { |cmd| cmd.join(' ') }.join(' | ')
    msgpack = CommandMessage.new(cmd_string, block_duration, lifetime_duration)
    DatabaseLogger.append_command(msgpack)

    # Dual-mode logging with sampling
    if DatabaseLogger.should_log?
      if DatabaseLogger.structured_logging && DatabaseLogger.logger
        duration_ms = (block_duration / 1000.0).round(2)
        db_num = if config.respond_to?(:db)
                   config.db
                 elsif config.is_a?(Hash)
                   config[:db]
                 end
        DatabaseLogger.logger.trace(
          "Redis pipeline commands=#{commands.size} duration_μs=#{block_duration} " \
          "duration_ms=#{duration_ms} timeline=#{lifetime_duration} " \
          "db=#{db_num} index=#{DatabaseLogger.index}"
        )
      elsif DatabaseLogger.logger
        message = format('[%s] %s', DatabaseLogger.index, msgpack.inspect)
        DatabaseLogger.logger.trace(message)
      end
    end

    # Notify instrumentation hooks
    if defined?(Familia::Instrumentation)
      duration_ms = (block_duration / 1000.0).round(2)
      db_num = if config.respond_to?(:db)
                   config.db
                 elsif config.is_a?(Hash)
                   config[:db]
                 end
      conn_id = if config.respond_to?(:custom)
                   config.custom&.dig(:id)
                 elsif config.is_a?(Hash)
                   config.dig(:custom, :id)
                 end
      Familia::Instrumentation.notify_pipeline(
        commands.size,
        duration_ms,
        db: db_num,
        connection_id: conn_id
      )
    end

    results
  end

  # Handle call_once for commands requiring dedicated connection handling:
  #
  # * Blocking commands (BLPOP, BRPOP, BRPOPLPUSH)
  # * Pub/sub operations (SUBSCRIBE, PSUBSCRIBE)
  # * Commands requiring connection affinity
  # * Explicit non-pooled command execution
  #
  # @param command [Array] The Redis command and its arguments
  # @param config [RedisClient::Config, Hash] Connection configuration
  # @return [Object] The result of the Redis command execution
  def call_once(command, config)
    block_start = DatabaseLogger.now_in_μs
    result = yield  # CRITICAL: For call_once, yield is correct (not chaining)
    block_duration = DatabaseLogger.now_in_μs - block_start
    lifetime_duration = (Time.now.to_f - DatabaseLogger.process_start).round(6)

    msgpack = CommandMessage.new(command.join(' '), block_duration, lifetime_duration)
    DatabaseLogger.append_command(msgpack)

    # Dual-mode logging with sampling
    if DatabaseLogger.should_log?
      if DatabaseLogger.structured_logging && DatabaseLogger.logger
        duration_ms = (block_duration / 1000.0).round(2)
        db_num = if config.respond_to?(:db)
                   config.db
                 elsif config.is_a?(Hash)
                   config[:db]
                 end
        DatabaseLogger.logger.trace(
          "Redis command_once cmd=#{command.first} args=#{command[1..-1].inspect} " \
          "duration_μs=#{block_duration} duration_ms=#{duration_ms} " \
          "timeline=#{lifetime_duration} db=#{db_num} index=#{DatabaseLogger.index}"
        )
      elsif DatabaseLogger.logger
        message = format('[%s] %s', DatabaseLogger.index, msgpack.inspect)
        DatabaseLogger.logger.trace(message)
      end
    end

    result
  end
end
# rubocop:enable ThreadSafety/ClassInstanceVariable
