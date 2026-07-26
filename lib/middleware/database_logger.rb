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
  @process_start = Time.now.utc.to_f.freeze
  @structured_logging = false
  @sample_rate = nil  # nil = log everything, 0.1 = 10%, 0.01 = 1%
  @sample_counter = Concurrent::AtomicFixnum.new(0)
  @commands_mutex = Mutex.new  # Protects compound operations on @commands
  @capture_enabled = true  # true = capture every command into the buffer

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

    # Gets/sets whether commands are captured into the buffer.
    #
    # This toggle is independent of {#sample_rate}, which governs only log
    # output. Capture controls whether each command pays the cost of timing,
    # CommandMessage allocation, and the buffer append.
    #
    # @return [Boolean] Whether command capture is enabled (default true)
    #
    # @example Development / test (default) — full capture for assertions
    #   DatabaseLogger.capture_enabled = true
    #   # every command captured; capture_commands works as usual
    #
    # @example Production — sampled logging, no buffer/timing overhead
    #   DatabaseLogger.sample_rate = 0.01
    #   DatabaseLogger.capture_enabled = false
    #   # 1% of commands logged; unsampled commands take the zero-overhead
    #   # fast path (no clock_gettime, no allocation, no buffer append) unless
    #   # an instrumentation hook is registered
    #
    # @note When false, a command that is also not sampled for logging and has
    #   no registered instrumentation hook skips timing entirely. Log output
    #   still follows sample_rate, and instrumentation hooks still fire at full
    #   rate (timing is measured whenever a hook is registered).
    attr_accessor :capture_enabled

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

    # Maps a middleware mode to the instrumentation hook type it reports to,
    # or nil when that mode emits no instrumentation.
    #
    # This is the SINGLE SOURCE OF TRUTH for the per-mode instrumentation
    # contract. Both the fast-path decision ({#measure?}) and the notify step
    # ({#record}) consult it, so a mode can never end up measuring without
    # notifying (wasted work) or notifying from a fast-pathed call (a silently
    # dropped hook). +:once+ returns nil because +call_once+ does not emit
    # instrumentation today; to change that, flip this one method and both the
    # fast path and the notify step update together.
    #
    # @param mode [Symbol] :call, :once, or :pipeline
    # @return [Symbol, nil] :command, :pipeline, or nil
    # @api private
    def hook_type_for(mode)
      case mode
      when :pipeline then :pipeline
      when :call then :command
      when :once then nil # call_once emits no instrumentation today
      end
    end

    # Whether any instrumentation hooks are registered for +type+.
    #
    # Guards against +Familia::Instrumentation+ being undefined, then defers to
    # its +hooks?+ predicate. A +defined?+ check alone cannot gate the fast path
    # because the module is always loaded.
    #
    # @param type [Symbol, nil] hook type, or nil for "no instrumentation"
    # @return [Boolean]
    # @api private
    def hooks_active?(type)
      return false if type.nil?

      defined?(Familia::Instrumentation) && Familia::Instrumentation.hooks?(type)
    end

    # Decide whether an invocation needs the measured (non-fast) path.
    #
    # Returns true when capture is enabled, the command is sampled for logging,
    # or a relevant instrumentation hook is registered. When all three are
    # false the caller takes the zero-overhead fast path (no clock_gettime, no
    # CommandMessage allocation, no buffer append).
    #
    # @param should_log [Boolean] result of the single per-command should_log?
    #   call (passed in so the sampling counter is advanced exactly once)
    # @param mode [Symbol] :call, :once, or :pipeline
    # @return [Boolean]
    # @api private
    def measure?(should_log:, mode:)
      @capture_enabled || should_log || hooks_active?(hook_type_for(mode))
    end

    # Record a measured command: buffer it, emit a sampled log line, and fire
    # the instrumentation hook. Called only on the measured path, after the
    # wrapped command has executed and been timed.
    #
    # @param raw [Array] the single command array (:call/:once) or the array of
    #   command arrays (:pipeline)
    # @param config connection configuration
    # @param duration [Integer] measured execution time in microseconds
    # @param mode [Symbol] :call, :once, or :pipeline
    # @param should_log [Boolean] the per-command should_log? result
    # @return [nil]
    # @api private
    def record(raw, config, duration, mode:, should_log:)
      lifetime = (Familia.now.to_f - @process_start).round(6)

      # Build the CommandMessage only when capturing or logging needs it; append
      # to the buffer only when capture is enabled. The hook-only path (capture
      # off, not sampled, but a hook is registered) skips the buffer entirely.
      msgpack = nil
      if @capture_enabled || should_log
        msgpack = CommandMessage.new(command_string(raw, mode), duration, lifetime)
        append_command(msgpack) if @capture_enabled
      end

      emit_log(raw, config, duration, lifetime, mode, msgpack) if should_log && @logger

      hook = hook_type_for(mode)
      notify_hook(raw, config, duration, hook) if hooks_active?(hook)

      nil
    end

    # Emits a single sampled log line: structured key=value context, or the
    # legacy "[index] timeline durationμs > command" format.
    # @api private
    def emit_log(raw, config, duration, lifetime, mode, msgpack)
      message = if @structured_logging
                  structured_log_message(raw, config, duration, lifetime, mode)
                else
                  format('[%s] %s', index, msgpack.inspect)
                end
      @logger.trace(message)
    end

    # @api private
    def command_string(raw, mode)
      if mode == :pipeline
        raw.map { |cmd| cmd.join(' ') }.join(' | ')
      else
        raw.join(' ')
      end
    end

    # Extracts [db, connection_id] from either a RedisClient::Config or a Hash.
    # @api private
    def connection_meta(config)
      db = if config.respond_to?(:db)
             config.db
           elsif config.is_a?(Hash)
             config[:db]
           end
      conn_id = if config.respond_to?(:custom)
                  config.custom&.dig(:id)
                elsif config.is_a?(Hash)
                  config.dig(:custom, :id)
                end
      [db, conn_id]
    end

    # @api private
    def structured_log_message(raw, config, duration, lifetime, mode)
      duration_ms = (duration / 1000.0).round(2)
      db_num, = connection_meta(config)
      common = "duration_μs=#{duration} duration_ms=#{duration_ms} " \
               "timeline=#{lifetime} db=#{db_num} index=#{index}"

      case mode
      when :pipeline
        "Redis pipeline commands=#{raw.size} #{common}"
      when :once
        "Redis command_once cmd=#{raw.first} args=#{raw[1..].inspect} #{common}"
      else
        "Redis command cmd=#{raw.first} args=#{raw[1..].inspect} #{common}"
      end
    end

    # @api private
    def notify_hook(raw, config, duration, hook)
      duration_ms = (duration / 1000.0).round(2)
      db_num, conn_id = connection_meta(config)

      if hook == :pipeline
        Familia::Instrumentation.notify_pipeline(
          raw.size, duration_ms, db: db_num, connection_id: conn_id
        )
      else
        Familia::Instrumentation.notify_command(
          raw.first, duration_ms,
          full_command: raw, db: db_num, connection_id: conn_id
        )
      end
    end
  end

  # Logs the Redis command and its execution time.
  #
  # This method is part of the RedisClient middleware chain. It MUST use `super`
  # instead of `yield` to properly chain with other middlewares. The shared
  # decision/record logic lives in {DatabaseLogger.measure?} and
  # {DatabaseLogger.record}; only the execution+timing skeleton stays here so
  # the fast path remains allocation-free and `super` keeps chaining.
  #
  # @param command [Array] The Redis command and its arguments
  # @param config [RedisClient::Config, Hash] Connection configuration
  # @return [Object] The result of the Redis command execution
  #
  # @note should_log? is evaluated exactly once per command to keep the sampling
  #   counter deterministic. On the fast path nothing is timed or allocated.
  def call(command, config)
    should_log = DatabaseLogger.should_log?
    return super unless DatabaseLogger.measure?(should_log: should_log, mode: :call)

    block_start = DatabaseLogger.now_in_μs
    result = super  # CRITICAL: Must use super, not yield, to chain middlewares
    duration = DatabaseLogger.now_in_μs - block_start

    DatabaseLogger.record(command, config, duration, mode: :call, should_log: should_log)
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
    should_log = DatabaseLogger.should_log?
    return yield unless DatabaseLogger.measure?(should_log: should_log, mode: :pipeline)

    block_start = DatabaseLogger.now_in_μs
    results = yield  # CRITICAL: For call_pipelined, yield is correct (not chaining)
    duration = DatabaseLogger.now_in_μs - block_start

    DatabaseLogger.record(commands, config, duration, mode: :pipeline, should_log: should_log)
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
  #
  # @note call_once shares the same record path as #call. Whether it emits
  #   instrumentation is governed entirely by {DatabaseLogger.hook_type_for}
  #   (currently :once => nil), so the fast-path decision and the notify step
  #   stay in lockstep.
  def call_once(command, config)
    should_log = DatabaseLogger.should_log?
    return yield unless DatabaseLogger.measure?(should_log: should_log, mode: :once)

    block_start = DatabaseLogger.now_in_μs
    result = yield  # CRITICAL: For call_once, yield is correct (not chaining)
    duration = DatabaseLogger.now_in_μs - block_start

    DatabaseLogger.record(command, config, duration, mode: :once, should_log: should_log)
    result
  end
end
# rubocop:enable ThreadSafety/ClassInstanceVariable
