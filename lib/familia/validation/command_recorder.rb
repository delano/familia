# lib/familia/validation/command_recorder.rb

require 'concurrent-ruby'

module Familia
  module Validation
    # Enhanced command recorder that captures Valkey/Redis commands with full context
    # for validation purposes. Extends the existing DatabaseLogger functionality
    # to provide detailed command tracking including transaction boundaries.
    #
    # @example Basic usage
    #   CommandRecorder.start_recording
    #   # ... perform db operations
    #   commands = CommandRecorder.stop_recording
    #   puts commands.map(&:to_s)
    #
    # @example Transaction recording
    #   CommandRecorder.start_recording
    #   Familia.transaction do |conn|
    #     conn.hset("key", "field", "value")
    #     conn.incr("counter")
    #   end
    #   commands = CommandRecorder.stop_recording
    #   commands.transaction_blocks.length #=> 1
    #   commands.transaction_blocks.first.commands.length #=> 2
    #
    module CommandRecorder
      extend self

      # Thread-safe recording state
      @recording_state = Concurrent::ThreadLocalVar.new { false }
      @recorded_commands = Concurrent::ThreadLocalVar.new { CommandSequence.new }
      @transaction_stack = Concurrent::ThreadLocalVar.new { [] }
      @pipeline_stack = Concurrent::ThreadLocalVar.new { [] }

      # Represents a single Valkey/Redis command with full context
      class RecordedCommand
        attr_reader :command, :args, :result, :timestamp, :duration_us, :context, :command_type

        def initialize(command:, args:, result:, timestamp:, duration_us:, context: {})
          @command = command.to_s.upcase
          @args = args.dup.freeze
          @result = result
          @timestamp = timestamp
          @duration_us = duration_us
          @context = context.dup.freeze
          @command_type = determine_command_type
        end

        def to_s
          args_str = @args.map(&:inspect).join(', ')
          "#{@command}(#{args_str})"
        end

        def to_h
          {
            command: @command,
            args: @args,
            result: @result,
            timestamp: @timestamp,
            duration_us: @duration_us,
            context: @context,
            command_type: @command_type
          }
        end

        def transaction_command?
          %w[MULTI EXEC DISCARD].include?(@command)
        end

        def pipeline_command?
          @context[:pipeline] == true
        end

        def atomic_command?
          @context[:transaction] == true
        end

        private

        def determine_command_type
          case @command
          when 'MULTI', 'EXEC', 'DISCARD'
            :transaction_control
          when 'PIPELINE'
            :pipeline_control
          when /^H(GET|SET|DEL|EXISTS|KEYS|LEN|MGET|MSET)/
            :hash
          when /^(L|R)(PUSH|POP|LEN|RANGE|INDEX|SET|REM)/
            :list
          when /^S(ADD|REM|MEMBERS|CARD|ISMEMBER|DIFF|INTER|UNION)/
            :set
          when /^Z(ADD|REM|RANGE|SCORE|CARD|COUNT|RANK|INCR)/
            :sorted_set
          when /^(GET|SET|DEL|EXISTS|EXPIRE|TTL|TYPE|INCR|DECR)/
            :string
          else
            :other
          end
        end
      end

      # Represents a sequence of Valkey/Redis commands with transaction boundaries
      class CommandSequence
        attr_reader :commands, :transaction_blocks, :pipeline_blocks

        def initialize
          @commands = []
          @transaction_blocks = []
          @pipeline_blocks = []
        end

        def add_command(recorded_command)
          @commands << recorded_command
        end

        def start_transaction(context = {})
          @transaction_blocks << TransactionBlock.new(context)
        end

        def end_transaction
          return unless current_transaction

          current_transaction.finalize(@commands)
        end

        def start_pipeline(context = {})
          @pipeline_blocks << PipelineBlock.new(context)
        end

        def end_pipeline
          return unless current_pipeline

          current_pipeline.finalize(@commands)
        end

        def current_transaction
          @transaction_blocks.last
        end

        def current_pipeline
          @pipeline_blocks.last
        end

        def command_count
          @commands.length
        end

        def transaction_count
          @transaction_blocks.length
        end

        def pipeline_count
          @pipeline_blocks.length
        end

        def to_a
          @commands
        end

        def clear
          @commands.clear
          @transaction_blocks.clear
          @pipeline_blocks.clear
        end
      end

      # Represents a transaction block (MULTI/EXEC)
      class TransactionBlock
        attr_reader :start_index, :end_index, :commands, :context, :started_at

        def initialize(context = {})
          @context = context
          @started_at = Familia.now
          @start_index = nil
          @end_index = nil
          @commands = []
        end

        def finalize(all_commands)
          # Find MULTI and EXEC commands
          multi_index = all_commands.rindex { |cmd| cmd.command == 'MULTI' }
          exec_index = all_commands.rindex { |cmd| cmd.command == 'EXEC' }

          return unless multi_index && exec_index && exec_index > multi_index

          @start_index = multi_index
          @end_index = exec_index
          @commands = all_commands[(multi_index + 1)...exec_index]
        end

        def valid?
          @start_index && @end_index && @commands.any?
        end

        def command_count
          @commands.length
        end
      end

      # Represents a pipeline block
      class PipelineBlock
        attr_reader :commands, :context, :started_at

        def initialize(context = {})
          @context = context
          @started_at = Familia.now
          @commands = []
        end

        def finalize(all_commands)
          # Pipeline commands are those executed within pipeline context
          @commands = all_commands.select(&:pipeline_command?)
        end

        def command_count
          @commands.length
        end
      end

      # Start recording Valkey/Redis commands for the current thread
      def start_recording
        @recording_state.value = true
        @recorded_commands.value = CommandSequence.new
        @transaction_stack.value = []
        @pipeline_stack.value = []
      end

      # Stop recording and return the recorded command sequence
      def stop_recording
        @recording_state.value = false
        sequence = @recorded_commands.value
        @recorded_commands.value = CommandSequence.new
        sequence
      end

      # Check if currently recording
      def recording?
        @recording_state.value == true
      end

      # Record a Valkey/Redis command with full context
      def record_command(command:, args:, result:, timestamp:, duration_us:, context: {})
        return unless recording?

        # Enhance context with transaction/pipeline state
        enhanced_context = context.merge(
          transaction: in_transaction?,
          pipeline: in_pipeline?,
          transaction_depth: transaction_depth,
          pipeline_depth: pipeline_depth
        )

        recorded_cmd = RecordedCommand.new(
          command: command,
          args: args,
          result: result,
          timestamp: timestamp,
          duration_us: duration_us,
          context: enhanced_context
        )

        sequence = @recorded_commands.value
        sequence.add_command(recorded_cmd)

        # Handle transaction boundaries
        case recorded_cmd.command
        when 'MULTI'
          sequence.start_transaction(enhanced_context)
          @transaction_stack.value.push(Familia.now)
        when 'EXEC', 'DISCARD'
          sequence.end_transaction if sequence.current_transaction
          @transaction_stack.value.pop
        end
      end

      # Check if we're currently in a transaction
      def in_transaction?
        @transaction_stack.value.any?
      end

      # Check if we're currently in a pipeline
      def in_pipeline?
        @pipeline_stack.value.any?
      end

      # Get current transaction nesting depth
      def transaction_depth
        @transaction_stack.value.length
      end

      # Get current pipeline nesting depth
      def pipeline_depth
        @pipeline_stack.value.length
      end

      # Get the current command sequence (for inspection during recording)
      def current_sequence
        @recorded_commands.value
      end

      # Clear all recorded data
      def clear
        @recorded_commands.value.clear
      end

      # Enhanced middleware that integrates with DatabaseLogger
      module Middleware
        def self.call(command, config)
          return yield unless CommandRecorder.recording?

          timestamp = Familia.now
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)

          result = yield

          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start_time

          CommandRecorder.record_command(
            command: command[0],
            args: command[1..-1],
            result: result,
            timestamp: timestamp,
            duration_us: duration,
            context: {
              config: config,
              thread_id: Thread.current.object_id
            }
          )

          result
        end
      end
    end
  end
end
