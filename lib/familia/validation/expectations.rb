# lib/familia/validation/expectations.rb

module Familia
  module Validation
    # Fluent DSL for defining expected Redis command sequences with support
    # for transaction and pipeline validation. Provides a readable way to
    # specify expected database operations and verify they execute correctly.
    #
    # @example Basic command expectations
    #   expectation = CommandExpectations.new
    #   expectation.hset("user:123", "name", "John")
    #              .incr("user:counter")
    #              .expire("user:123", 3600)
    #
    #   # Validate against actual commands
    #   result = expectation.validate(actual_commands)
    #   result.valid? #=> true/false
    #
    # @example Transaction expectations
    #   expectation = CommandExpectations.new
    #   expectation.transaction do |tx|
    #     tx.hset("user:123", "name", "John")
    #       .incr("counter")
    #   end
    #
    # @example Pattern matching
    #   expectation = CommandExpectations.new
    #   expectation.hset(any_string, "name", any_string)
    #              .match_pattern(/^INCR/)
    #
    class CommandExpectations
      attr_reader :expected_commands, :transaction_blocks, :pipeline_blocks

      def initialize
        @expected_commands = []
        @transaction_blocks = []
        @pipeline_blocks = []
        @current_transaction = nil
        @current_pipeline = nil
        @options = {
          strict_order: true,
          exact_match: true,
          allow_extra_commands: false
        }
      end

      # Configuration methods
      def strict_order(enabled = true)
        @options[:strict_order] = enabled
        self
      end

      def exact_match(enabled = true)
        @options[:exact_match] = enabled
        self
      end

      def allow_extra_commands(enabled = true)
        @options[:allow_extra_commands] = enabled
        self
      end

      # Transaction block expectation
      def transaction(&block)
        @current_transaction = TransactionExpectation.new(@options)
        @transaction_blocks << @current_transaction

        if block_given?
          block.call(@current_transaction)
          @current_transaction = nil
        end

        self
      end

      # Pipeline block expectation
      def pipeline(&block)
        @current_pipeline = PipelineExpectation.new(@options)
        @pipeline_blocks << @current_pipeline

        if block_given?
          block.call(@current_pipeline)
          @current_pipeline = nil
        end

        self
      end

      # Redis command expectations - these can be chained
      %w[
        get set del exists expire ttl type incr decr
        hget hset hdel hexists hkeys hvals hlen hmget hmset
        lpush rpush lpop rpop llen lrange lindex lset lrem
        sadd srem sismember smembers scard sdiff sinter sunion
        zadd zrem zscore zrange zrank zcard zcount
        multi exec discard
      ].each do |cmd|
        define_method(cmd.to_sym) do |*args|
          add_command_expectation(cmd.upcase, args)
        end
      end

      # Generic command expectation
      def command(cmd, *args)
        add_command_expectation(cmd.to_s.upcase, args)
      end

      # Pattern matching for flexible expectations
      def match_pattern(pattern, description = nil)
        expectation = PatternExpectation.new(pattern, description)
        add_expectation(expectation)
      end

      # Validate against actual recorded commands
      def validate(command_sequence)
        ValidationResult.new(self, command_sequence).validate
      end

      # Helper methods for common patterns
      def any_string
        ArgumentMatcher.new(:any_string)
      end

      def any_number
        ArgumentMatcher.new(:any_number)
      end

      def any_value
        ArgumentMatcher.new(:any_value)
      end

      def match_regex(pattern)
        ArgumentMatcher.new(:regex, pattern)
      end

      private

      def add_command_expectation(cmd, args)
        expectation = CommandExpectation.new(cmd, args)
        add_expectation(expectation)
      end

      def add_expectation(expectation)
        target = @current_transaction || @current_pipeline || self

        if target == self
          @expected_commands << expectation
        else
          target.add_expectation(expectation)
        end

        self
      end
    end

    # Represents an expected Redis command
    class CommandExpectation
      attr_reader :command, :args, :options

      def initialize(command, args, options = {})
        @command = command.to_s.upcase
        @args = args
        @options = options
      end

      def matches?(recorded_command)
        return false unless command_matches?(recorded_command)
        return false unless args_match?(recorded_command)

        true
      end

      def to_s
        args_str = @args.map { |arg| format_arg(arg) }.join(', ')
        "#{@command}(#{args_str})"
      end

      private

      def command_matches?(recorded_command)
        @command == recorded_command.command
      end

      def args_match?(recorded_command)
        return true if @args.empty? && recorded_command.args.empty?
        return false if @args.length != recorded_command.args.length

        @args.zip(recorded_command.args).all? do |expected, actual|
          argument_matches?(expected, actual)
        end
      end

      def argument_matches?(expected, actual)
        case expected
        when ArgumentMatcher
          expected.matches?(actual)
        else
          expected.to_s == actual.to_s
        end
      end

      def format_arg(arg)
        case arg
        when ArgumentMatcher
          arg.to_s
        else
          arg.inspect
        end
      end
    end

    # Represents a pattern-based expectation
    class PatternExpectation
      attr_reader :pattern, :description

      def initialize(pattern, description = nil)
        @pattern = pattern
        @description = description || pattern.to_s
      end

      def matches?(recorded_command)
        case @pattern
        when Regexp
          @pattern.match?(recorded_command.to_s)
        when String
          recorded_command.to_s.include?(@pattern)
        when Proc
          @pattern.call(recorded_command)
        else
          false
        end
      end

      def to_s
        "pattern(#{@description})"
      end
    end

    # Transaction expectation block
    class TransactionExpectation
      attr_reader :expected_commands

      def initialize(options = {})
        @expected_commands = []
        @options = options
      end

      def add_expectation(expectation)
        @expected_commands << expectation
        self
      end

      # Support all the same command methods
      CommandExpectations.instance_methods(false).each do |method|
        next if [:validate, :transaction, :pipeline].include?(method)
        next unless method.to_s.match?(/^[a-z]/)

        define_method(method) do |*args|
          CommandExpectations.new.send(method, *args)
          add_expectation(CommandExpectation.new(method.to_s, args))
        end
      end

      def validate_transaction(transaction_block)
        return false unless transaction_block.valid?

        expected_count = @expected_commands.length
        actual_count = transaction_block.command_count

        return false if @options[:exact_match] && expected_count != actual_count
        return false if expected_count > actual_count

        if @options[:strict_order]
          validate_strict_order(transaction_block.commands)
        else
          validate_flexible_order(transaction_block.commands)
        end
      end

      private

      def validate_strict_order(commands)
        commands.zip(@expected_commands).all? do |actual, expected|
          expected&.matches?(actual)
        end
      end

      def validate_flexible_order(commands)
        expected_copy = @expected_commands.dup

        commands.all? do |actual|
          match_index = expected_copy.find_index { |expected| expected.matches?(actual) }
          next false unless match_index

          expected_copy.delete_at(match_index)
          true
        end
      end
    end

    # Pipeline expectation block (similar to transaction but for pipelines)
    class PipelineExpectation < TransactionExpectation
      def validate_pipeline(pipeline_block)
        validate_flexible_order(pipeline_block.commands)
      end
    end

    # Argument matcher for flexible command argument validation
    class ArgumentMatcher
      attr_reader :type, :options

      def initialize(type, *options)
        @type = type
        @options = options
      end

      def matches?(value)
        case @type
        when :any_string
          value.is_a?(String)
        when :any_number
          value.to_s.match?(/^\d+$/)
        when :any_value
          true
        when :regex
          @options.first.match?(value.to_s)
        else
          false
        end
      end

      def to_s
        case @type
        when :any_string
          '<any_string>'
        when :any_number
          '<any_number>'
        when :any_value
          '<any_value>'
        when :regex
          "<match:#{@options.first}>"
        else
          "<#{@type}>"
        end
      end
    end

    # Result of validation with detailed information
    class ValidationResult
      attr_reader :expectations, :command_sequence, :errors, :warnings

      def initialize(expectations, command_sequence)
        @expectations = expectations
        @command_sequence = command_sequence
        @errors = []
        @warnings = []
        @valid = nil
      end

      def validate
        @valid = perform_validation
        self
      end

      def valid?
        @valid == true
      end

      def error_messages
        @errors
      end

      def warning_messages
        @warnings
      end

      def summary
        {
          valid: valid?,
          expected_commands: @expectations.expected_commands.length,
          actual_commands: @command_sequence.command_count,
          expected_transactions: @expectations.transaction_blocks.length,
          actual_transactions: @command_sequence.transaction_count,
          errors: @errors.length,
          warnings: @warnings.length
        }
      end

      def detailed_report
        report = ["Redis Command Validation Report", "=" * 40]
        report << "Status: #{valid? ? 'PASS' : 'FAIL'}"
        report << ""

        if valid?
          report << "All expectations matched successfully!"
        else
          report << "Validation Errors:"
          @errors.each_with_index do |error, i|
            report << "  #{i + 1}. #{error}"
          end
        end

        if @warnings.any?
          report << ""
          report << "Warnings:"
          @warnings.each_with_index do |warning, i|
            report << "  #{i + 1}. #{warning}"
          end
        end

        report << ""
        report << "Summary:"
        summary.each do |key, value|
          report << "  #{key}: #{value}"
        end

        report.join("\n")
      end

      private

      def perform_validation
        validate_command_count
        validate_transaction_blocks
        validate_command_sequence

        @errors.empty?
      end

      def validate_command_count
        expected = @expectations.expected_commands.length
        actual = @command_sequence.command_count

        if expected > actual
          @errors << "Expected #{expected} commands, but only #{actual} were executed"
        elsif expected < actual && !@expectations.instance_variable_get(:@options)[:allow_extra_commands]
          @warnings << "Expected #{expected} commands, but #{actual} were executed (extra commands)"
        end
      end

      def validate_transaction_blocks
        expected_tx = @expectations.transaction_blocks
        actual_tx = @command_sequence.transaction_blocks

        if expected_tx.length != actual_tx.length
          @errors << "Expected #{expected_tx.length} transactions, but #{actual_tx.length} were executed"
          return
        end

        expected_tx.zip(actual_tx).each_with_index do |(expected, actual), i|
          unless expected.validate_transaction(actual)
            @errors << "Transaction #{i + 1} did not match expectations"
          end
        end
      end

      def validate_command_sequence
        return if @expectations.expected_commands.empty?

        expected_commands = @expectations.expected_commands
        actual_commands = @command_sequence.commands

        if @expectations.instance_variable_get(:@options)[:strict_order]
          validate_strict_command_order(expected_commands, actual_commands)
        else
          validate_flexible_command_order(expected_commands, actual_commands)
        end
      end

      def validate_strict_command_order(expected, actual)
        expected.each_with_index do |expected_cmd, i|
          actual_cmd = actual[i]

          unless actual_cmd
            @errors << "Expected command #{expected_cmd} at position #{i + 1}, but no command was executed"
            next
          end

          unless expected_cmd.matches?(actual_cmd)
            @errors << "Command mismatch at position #{i + 1}: expected #{expected_cmd}, got #{actual_cmd}"
          end
        end
      end

      def validate_flexible_command_order(expected, actual)
        expected_copy = expected.dup
        unmatched_actual = []

        actual.each do |actual_cmd|
          match_index = expected_copy.find_index { |expected_cmd| expected_cmd.matches?(actual_cmd) }

          if match_index
            expected_copy.delete_at(match_index)
          else
            unmatched_actual << actual_cmd
          end
        end

        expected_copy.each do |unmatched_expected|
          @errors << "Expected command #{unmatched_expected} was not executed"
        end

        unmatched_actual.each do |unexpected_actual|
          @warnings << "Unexpected command executed: #{unexpected_actual}"
        end
      end
    end
  end
end
