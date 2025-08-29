# lib/familia/validation/validator.rb

module Familia
  module Validation
    # Main validation engine that orchestrates command recording and validation.
    # Provides high-level interface for validating Redis operations against
    # expectations with detailed reporting and atomicity verification.
    #
    # @example Basic validation
    #   validator = Validator.new
    #
    #   result = validator.validate do |expect|
    #     # Define expectations
    #     expect.hset("user:123", "name", "John")
    #           .incr("counter")
    #
    #     # Execute code under test
    #     user = User.new(id: "123", name: "John")
    #     user.save
    #     Counter.increment
    #   end
    #
    #   puts result.valid? ? "PASS" : "FAIL"
    #   puts result.detailed_report
    #
    # @example Transaction validation
    #   validator = Validator.new
    #
    #   result = validator.validate do |expect|
    #     expect.transaction do |tx|
    #       tx.hset("user:123", "name", "John")
    #         .incr("counter")
    #     end
    #
    #     # Code should execute atomically
    #     Familia.transaction do |conn|
    #       conn.hset("user:123", "name", "John")
    #       conn.incr("counter")
    #     end
    #   end
    #
    class Validator
      attr_reader :options

      def initialize(options = {})
        @options = {
          auto_register_middleware: true,
          strict_atomicity: true,
          performance_tracking: true,
          command_filtering: :all # :all, :familia_only, :custom
        }.merge(options)

        register_middleware if @options[:auto_register_middleware]
      end

      # Main validation method - records commands and validates against expectations
      def validate(&block)
        raise ArgumentError, "Block required for validation" unless block_given?

        expectations = nil
        command_sequence = nil

        begin
          # Start recording commands
          CommandRecorder.start_recording
          register_middleware_if_needed

          # Execute the validation block
          expectations = CommandExpectations.new
          block.call(expectations)

          # Get recorded commands
          command_sequence = CommandRecorder.stop_recording

        rescue => e
          CommandRecorder.stop_recording
          raise ValidationError, "Validation failed with error: #{e.message}"
        end

        # Validate and return result
        result = expectations.validate(command_sequence)

        if @options[:performance_tracking]
          add_performance_metrics(result, command_sequence)
        end

        if @options[:strict_atomicity]
          validate_atomicity(result, command_sequence)
        end

        result
      end

      # Validate that specific code executes expected Redis commands
      def validate_execution(expectations_block, execution_block)
        expectations = CommandExpectations.new
        expectations_block.call(expectations)

        CommandRecorder.start_recording
        register_middleware_if_needed

        begin
          execution_block.call
          command_sequence = CommandRecorder.stop_recording
        rescue => e
          CommandRecorder.stop_recording
          raise ValidationError, "Execution failed: #{e.message}"
        end

        result = expectations.validate(command_sequence)

        if @options[:performance_tracking]
          add_performance_metrics(result, command_sequence)
        end

        result
      end

      # Validate that code executes atomically (within transactions)
      def validate_atomicity(&block)
        CommandRecorder.start_recording
        register_middleware_if_needed

        begin
          block.call
          command_sequence = CommandRecorder.stop_recording
        rescue => e
          CommandRecorder.stop_recording
          raise ValidationError, "Atomicity validation failed: #{e.message}"
        end

        AtomicityValidator.new(command_sequence, @options).validate
      end

      # Assert that specific commands were executed
      def assert_commands_executed(expected_commands, actual_commands = nil)
        actual_commands ||= get_last_recorded_sequence

        expectations = CommandExpectations.new
        expected_commands.each do |cmd_spec|
          case cmd_spec
          when Array
            expectations.command(cmd_spec[0], *cmd_spec[1..-1])
          when Hash
            cmd_spec.each do |cmd, args|
              expectations.command(cmd, *Array(args))
            end
          when String
            expectations.match_pattern(cmd_spec)
          end
        end

        expectations.validate(actual_commands)
      end

      # Performance analysis of recorded commands
      def analyze_performance(command_sequence)
        PerformanceAnalyzer.new(command_sequence).analyze
      end

      private

      def register_middleware
        return if @middleware_registered

        # Register our command recording middleware
        RedisClient.register(CommandRecorder::Middleware) if defined?(RedisClient)
        @middleware_registered = true
      end

      def register_middleware_if_needed
        register_middleware unless @middleware_registered
      end

      def get_last_recorded_sequence
        CommandRecorder.current_sequence
      end

      def add_performance_metrics(result, command_sequence)
        analyzer = PerformanceAnalyzer.new(command_sequence)
        metrics = analyzer.analyze

        result.instance_variable_set(:@performance_metrics, metrics)

        # Add singleton methods to result
        result.define_singleton_method(:performance_metrics) { @performance_metrics }
        result.define_singleton_method(:total_duration_ms) { @performance_metrics[:total_duration_ms] }
        result.define_singleton_method(:command_efficiency) { @performance_metrics[:efficiency_score] }
      end

      def validate_atomicity(result, command_sequence)
        atomicity_validator = AtomicityValidator.new(command_sequence, @options)
        atomicity_result = atomicity_validator.validate

        unless atomicity_result.valid?
          result.instance_variable_get(:@errors).concat(atomicity_result.error_messages)
          result.instance_variable_get(:@warnings).concat(atomicity_result.warning_messages)
        end
      end
    end

    # Validates that operations that should be atomic actually execute within transactions
    class AtomicityValidator
      attr_reader :command_sequence, :options

      def initialize(command_sequence, options = {})
        @command_sequence = command_sequence
        @options = options
        @errors = []
        @warnings = []
      end

      def validate
        check_transaction_boundaries
        check_orphaned_commands
        check_nested_transactions

        ValidationResult.new(nil, @command_sequence).tap do |result|
          result.instance_variable_set(:@errors, @errors)
          result.instance_variable_set(:@warnings, @warnings)
          result.instance_variable_set(:@valid, @errors.empty?)
        end
      end

      private

      def check_transaction_boundaries
        @command_sequence.transaction_blocks.each_with_index do |tx_block, i|
          unless tx_block.valid?
            @errors << "Transaction block #{i + 1} is invalid (missing MULTI or EXEC)"
          end

          if tx_block.command_count == 0
            @warnings << "Transaction block #{i + 1} contains no commands"
          end
        end
      end

      def check_orphaned_commands
        # Commands that should be in transactions but aren't
        orphaned_commands = @command_sequence.commands.select do |cmd|
          !cmd.atomic_command? && should_be_atomic?(cmd)
        end

        orphaned_commands.each do |cmd|
          @warnings << "Command #{cmd} should be executed atomically but was not in a transaction"
        end
      end

      def check_nested_transactions
        transaction_depth = 0

        @command_sequence.commands.each do |cmd|
          case cmd.command
          when 'MULTI'
            transaction_depth += 1
            if transaction_depth > 1
              @errors << "Nested transactions detected - Redis does not support nested MULTI/EXEC"
            end
          when 'EXEC', 'DISCARD'
            transaction_depth -= 1
            if transaction_depth < 0
              @errors << "EXEC/DISCARD without matching MULTI command"
            end
          end
        end

        if transaction_depth > 0
          @errors << "Unclosed transaction detected - MULTI without matching EXEC/DISCARD"
        end
      end

      def should_be_atomic?(cmd)
        # Define patterns for commands that should typically be atomic
        atomic_patterns = [
          /^HSET.*counter/i,  # Counter updates
          /^INCR/i,           # Increments
          /^DECR/i,           # Decrements
          /batch_update/i     # Batch operations
        ]

        atomic_patterns.any? { |pattern| cmd.to_s.match?(pattern) }
      end
    end

    # Analyzes performance characteristics of recorded commands
    class PerformanceAnalyzer
      attr_reader :command_sequence

      def initialize(command_sequence)
        @command_sequence = command_sequence
      end

      def analyze
        {
          total_commands: @command_sequence.command_count,
          total_duration_ms: total_duration_ms,
          average_command_time_us: average_command_time,
          slowest_commands: slowest_commands(5),
          command_type_breakdown: command_type_breakdown,
          transaction_efficiency: transaction_efficiency,
          potential_n_plus_one: detect_n_plus_one_patterns,
          efficiency_score: calculate_efficiency_score
        }
      end

      private

      def total_duration_ms
        @command_sequence.commands.sum(&:duration_us) / 1000.0
      end

      def average_command_time
        return 0 if @command_sequence.command_count == 0

        total_time = @command_sequence.commands.sum(&:duration_us)
        total_time / @command_sequence.command_count
      end

      def slowest_commands(limit = 5)
        @command_sequence.commands
          .sort_by(&:duration_us)
          .reverse
          .first(limit)
          .map { |cmd| { command: cmd.to_s, duration_us: cmd.duration_us } }
      end

      def command_type_breakdown
        @command_sequence.commands
          .group_by(&:command_type)
          .transform_values(&:count)
      end

      def transaction_efficiency
        return { score: 1.0, details: "No transactions" } if @command_sequence.transaction_count == 0

        total_tx_commands = @command_sequence.transaction_blocks.sum(&:command_count)
        total_commands = @command_sequence.command_count
        tx_overhead = @command_sequence.transaction_count * 2 # MULTI + EXEC

        efficiency = total_tx_commands.to_f / (total_tx_commands + tx_overhead)

        {
          score: efficiency,
          total_transaction_commands: total_tx_commands,
          transaction_overhead: tx_overhead,
          details: "#{@command_sequence.transaction_count} transactions with #{total_tx_commands} commands"
        }
      end

      def detect_n_plus_one_patterns
        patterns = []

        # Look for repeated similar commands that could be batched
        command_groups = @command_sequence.commands.group_by { |cmd| cmd.command }

        command_groups.each do |command, commands|
          next unless commands.length > 3 # Threshold for N+1 detection

          # Check if commands are similar (same command, similar keys)
          if similar_commands?(commands)
            patterns << {
              command: command,
              count: commands.length,
              suggestion: "Consider batching #{command} operations"
            }
          end
        end

        patterns
      end

      def similar_commands?(commands)
        return false if commands.length < 2

        first_cmd = commands.first
        commands.drop(1).all? do |cmd|
          cmd.command == first_cmd.command &&
          cmd.args.length == first_cmd.args.length
        end
      end

      def calculate_efficiency_score
        base_score = 100.0

        # Penalize for potential N+1 patterns
        n_plus_one_penalty = detect_n_plus_one_patterns.sum { |pattern| pattern[:count] * 2 }

        # Penalize for non-atomic operations that should be atomic
        non_atomic_penalty = @command_sequence.commands.count { |cmd| !cmd.atomic_command? } * 1

        # Bonus for using transactions appropriately
        transaction_bonus = @command_sequence.transaction_count > 0 ? 10 : 0

        [base_score - n_plus_one_penalty - non_atomic_penalty + transaction_bonus, 0].max
      end
    end

    # Custom error class for validation failures
    class ValidationError < StandardError; end
  end
end
