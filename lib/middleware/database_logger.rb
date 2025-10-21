# lib/middleware/database_logger.rb

require 'concurrent-ruby'

# DatabaseLogger is Valkey/RedisClient middleware.
#
# This middleware addresses the need for detailed Database command logging, which
# was removed from the redis-rb gem due to performance concerns. However, in
# many development and debugging scenarios, the ability to log Database commands
# can be invaluable.
#
# @example Enable Database command logging
#   DatabaseLogger.logger = Logger.new(STDOUT)
#   RedisClient.register(DatabaseLogger)
#
# @example Capture commands for testing
#   commands = DatabaseLogger.capture_commands do
#     redis.set('key', 'value')
#     redis.get('key')
#   end
#   puts commands.first[:command]  # => ["SET", "key", "value"]
#
# @see https://github.com/redis-rb/redis-client?tab=readme-ov-file#instrumentation-and-middlewares
#
# @note While there were concerns about the performance impact of logging in
#   the redis-rb gem, this middleware is designed to be optional and can be
#   easily enabled or disabled as needed. The performance impact is minimal
#   when logging is disabled, and the benefits during development and debugging
#   often outweigh the slight performance cost when enabled.
module DatabaseLogger
  @logger = nil
  @commands = Concurrent::Array.new
  @max_commands = 10_000
  @process_start = Time.now.to_f.freeze
  @structured_logging = false
  @sample_rate = nil  # nil = log everything, 0.1 = 10%, 0.01 = 1%
  @sample_counter = Concurrent::AtomicFixnum.new(0)

  unless defined?(CommandMessage)
    CommandMessage = Data.define(:command, :μs, :timeline) do
      alias_method :to_a, :deconstruct
      def inspect
        cmd, duration, timeline = to_a
        format('%.6f %4dμs > %s', timeline, duration, cmd)
      end
    end
  end

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
    # @return [Array] Array of command hashes with :command, :duration, :timeline
    attr_reader :commands

    # Gets the timestamp when DatabaseLogger was loaded.
    # @return [Float] The timestamp when DatabaseLogger was loaded.
    attr_reader :process_start

    # Clears the captured commands array.
    # @return [Array] Empty array
    def clear_commands
      @commands.clear
      nil
    end

    # Captures commands in a block and returns them.
    # This is useful for testing to see what commands were executed.
    #
    # @yield [] The block of code to execute while capturing commands.
    # @return [Array] Array of captured commands with timing information.
    #   Each command is a hash with :command, :duration, :timestamp keys.
    #
    # @example Test what Redis commands your code executes
    #   commands = DatabaseLogger.capture_commands do
    #     my_library_method()
    #   end
    #   assert_equal "SET", commands.first[:command][0]
    #   assert commands.first[:duration] > 0
    def capture_commands
      clear_commands
      yield
      @commands.to_a
    end

    # Gets the current count of Database commands executed.
    # @return [Integer] The number of Database commands executed.
    def index
      @commands.size
    end

    # Thread-safe append with bounded size
    #
    # @param message [String] The message to append.
    # @return [Array] The updated array of commands.
    def append_command(message)
      @commands.shift if @commands.size >= @max_commands
      @commands << message
    end

    # Returns the current time in microseconds.
    # This is used to measure the duration of Database commands.
    #
    # Alias: now_in_microseconds
    #
    # @return [Integer] The current time in microseconds.
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

  # Logs the Database command and its execution time.
  #
  # This method is called for each Database command when the middleware is active.
  # It always captures commands for testing and logs them if a logger is set.
  #
  # @param command [Array] The Database command and its arguments.
  # @param config [Hash] The configuration options for the Valkey/Redis
  #   connection.
  # @return [Object] The result of the Database command execution.
  #
  # @note Commands are always captured with minimal overhead for testing purposes.
  #   Logging only occurs when DatabaseLogger.logger is set.
  def call(command, config)
    block_start = DatabaseLogger.now_in_μs
    result = yield
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
  def call_pipelined(commands, config)
    block_start = DatabaseLogger.now_in_μs
    results = yield
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

  # call_once is used for commands that need dedicated connection handling:
  #
  #   * Blocking commands (BLPOP, BRPOP, BRPOPLPUSH)
  #   * Pub/sub operations (SUBSCRIBE, PSUBSCRIBE)
  #   * Commands requiring connection affinity
  #   * Explicit non-pooled command execution
  #
  def call_once(command, config)
    block_start = DatabaseLogger.now_in_μs
    result = yield
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

# DatabaseCommandCounter is Valkey/RedisClient middleware.
#
# This middleware counts the number of Database commands executed. It can be
# useful for performance monitoring and debugging, allowing you to track
# the volume of Database operations in your application.
#
# @example Enable Database command counting
#   DatabaseCommandCounter.reset
#   RedisClient.register(DatabaseCommandCounter)
#
# @see https://github.com/redis-rb/redis-client?tab=readme-ov-file#instrumentation-and-middlewares
#
module DatabaseCommandCounter
  @count = Concurrent::AtomicFixnum.new(0)

  # We skip SELECT because depending on how the Familia is connecting to redis
  # the number of SELECT commands can be a lot or just a little. For example in
  # a configuration where there's a connection to each logical db, there's only
  # one when the connection is made. When using a provider of via thread local
  # it could theoretically double the number of statements executed.
  @skip_commands = ::Set.new(['SELECT']).freeze

  class << self
    # Gets the set of commands to skip counting.
    # @return [UnsortedSet] The commands that won't be counted.
    attr_reader :skip_commands

    # Gets the current count of Database commands executed.
    # @return [Integer] The number of Database commands executed.
    def count
      @count.value
    end

    # Resets the command count to zero.
    # This method is thread-safe.
    # @return [Integer] The reset count (always 0).
    def reset
      @count.value = 0
    end

    # Increments the command count.
    # This method is thread-safe.
    # @return [Integer] The new count after incrementing.
    def increment
      @count.increment
    end

    def skip_command?(command)
      skip_commands.include?(command.first.to_s.upcase)
    end

    # Counts the number of Database commands executed within a block.
    #
    # This method captures the command count before and after executing the
    # provided block, returning the difference. This is useful for measuring
    # how many Database commands are executed by a specific operation.
    #
    # @yield [] The block of code to execute while counting commands.
    # @return [Integer] The number of Database commands executed within the block.
    #
    # @example Count commands in a block
    #   commands_executed = DatabaseCommandCounter.count_commands do
    #     dbclient.set('key1', 'value1')
    #     dbclient.get('key1')
    #   end
    #   # commands_executed will be 2
    def count_commands
      start_count = count      # Capture the current command count before execution
      yield                    # Execute the provided block
      end_count = count        # Capture the command count after execution
      end_count - start_count  # Return the difference (commands executed in block)
    end
  end

  def klass
    DatabaseCommandCounter
  end

  # Counts the Database command and delegates its execution.
  #
  # This method is called for each Database command when the middleware is active.
  # It increments the command count (unless the command is in the skip list)
  # and then yields to execute the actual command.
  #
  # @param command [Array] The Database command and its arguments.
  # @param _config [Hash] The configuration options for the Database connection.
  # @return [Object] The result of the Database command execution.
  def call(command, _config)
    klass.increment unless klass.skip_command?(command)
    yield
  end

  def call_pipelined(commands, _config)
    # Count all commands in the pipeline (except skipped ones)
    commands.each do |command|
      klass.increment unless klass.skip_command?(command)
    end
    yield
  end

  def call_once(command, _config)
    klass.increment unless klass.skip_command?(command)
    yield
  end
end
# rubocop:enable ThreadSafety/ClassInstanceVariable
