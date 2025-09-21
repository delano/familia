# lib/familia/validation/validation_helpers.rb

module Familia
  module Validation
    # Test helper methods for integrating Redis command validation with
    # the tryouts testing framework. Provides easy-to-use assertion methods
    # and automatic setup/cleanup for command validation tests.
    #
    # @example Basic usage in a try file
    #   require_relative '../validation/validation_helpers'
    #   extend Familia::Validation::TestHelpers
    #
    #   ## User save should execute expected Redis commands
    #   user = TestUser.new(id: "123", name: "John")
    #
    #   assert_redis_commands do |expect|
    #     expect.hset("testuser:123:object", "name", "John")
    #           .hset("testuser:123:object", "id", "123")
    #
    #     user.save
    #   end
    #   #=> true
    #
    # @example Transaction validation
    #   assert_atomic_operation do |expect|
    #     expect.transaction do |tx|
    #       tx.hset("account:123", "balance", "1000")
    #         .hset("account:456", "balance", "2000")
    #     end
    #
    #     transfer_funds(from: "123", to: "456", amount: 500)
    #   end
    #   #=> true
    #
    module TestHelpers
      # Assert that a block executes the expected Redis commands
      def assert_redis_commands(message = nil, &block)
        validator = Validator.new
        result = validator.validate(&block)

        unless result.valid?
          error_msg = message || "Redis command validation failed"
          error_msg += "\n" + result.detailed_report
          raise ValidationError, error_msg
        end

        result.valid?
      end

      # Assert that a block executes Redis commands atomically
      def assert_atomic_operation(message = nil, &block)
        validator = Validator.new(strict_atomicity: true)

        if block.arity == 1
          # Block expects expectations parameter
          result = validator.validate(&block)
        else
          # Block is just execution code - validate atomicity only
          result = validator.validate_atomicity(&block)
        end

        unless result.valid?
          error_msg = message || "Atomic operation validation failed"
          error_msg += "\n" + result.detailed_report
          raise ValidationError, error_msg
        end

        result.valid?
      end

      # Assert that specific commands were executed (flexible order)
      def assert_commands_executed(*expected_commands)
        validator = Validator.new

        CommandRecorder.start_recording
        yield if block_given?
        actual_commands = CommandRecorder.stop_recording

        result = validator.assert_commands_executed(expected_commands, actual_commands)

        unless result.valid?
          error_msg = "Expected commands were not executed as specified"
          error_msg += "\n" + result.detailed_report
          raise ValidationError, error_msg
        end

        result.valid?
      end

      # Assert that no Redis commands were executed
      def assert_no_redis_commands(&block)
        CommandRecorder.start_recording
        block.call if block_given?
        commands = CommandRecorder.stop_recording

        unless commands.command_count == 0
          error_msg = "Expected no Redis commands, but #{commands.command_count} were executed:"
          commands.commands.each { |cmd| error_msg += "\n  #{cmd}" }
          raise ValidationError, error_msg
        end

        true
      end

      # Assert that a specific number of commands were executed
      def assert_command_count(expected_count, &block)
        CommandRecorder.start_recording
        block.call if block_given?
        commands = CommandRecorder.stop_recording

        actual_count = commands.command_count
        unless actual_count == expected_count
          error_msg = "Expected #{expected_count} Redis commands, but #{actual_count} were executed"
          raise ValidationError, error_msg
        end

        true
      end

      # Assert that commands were executed within a transaction
      def assert_transaction_used(&block)
        CommandRecorder.start_recording
        block.call if block_given?
        commands = CommandRecorder.stop_recording

        unless commands.transaction_count > 0
          error_msg = "Expected operations to use transactions, but none were found"
          raise ValidationError, error_msg
        end

        true
      end

      # Assert that commands were NOT executed within a transaction
      def assert_no_transaction_used(&block)
        CommandRecorder.start_recording
        block.call if block_given?
        commands = CommandRecorder.stop_recording

        unless commands.transaction_count == 0
          error_msg = "Expected operations to NOT use transactions, but #{commands.transaction_count} were found"
          raise ValidationError, error_msg
        end

        true
      end

      # Capture and return Redis commands without validation
      def capture_redis_commands(&block)
        CommandRecorder.start_recording
        block.call if block_given?
        CommandRecorder.stop_recording
      end

      # Performance assertion - assert operations complete within time limit
      def assert_performance_within(max_duration_ms, &block)
        start_time = Familia.now
        CommandRecorder.start_recording

        result = block.call if block_given?

        commands = CommandRecorder.stop_recording
        actual_duration_ms = (Familia.now - start_time) * 1000

        if actual_duration_ms > max_duration_ms
          error_msg = "Operation took #{actual_duration_ms.round(2)}ms, " \
                     "expected less than #{max_duration_ms}ms"
          raise ValidationError, error_msg
        end

        result
      end

      # Assert efficient command usage (no N+1 patterns)
      def assert_efficient_commands(&block)
        validator = Validator.new(performance_tracking: true)
        commands = capture_redis_commands(&block)

        analysis = validator.analyze_performance(commands)

        if analysis[:efficiency_score] < 70 # Threshold for acceptable efficiency
          error_msg = "Inefficient Redis command usage detected (score: #{analysis[:efficiency_score]})"

          if analysis[:potential_n_plus_one].any?
            error_msg += "\nPotential N+1 patterns:"
            analysis[:potential_n_plus_one].each do |pattern|
              error_msg += "\n  #{pattern[:command]}: #{pattern[:count]} calls - #{pattern[:suggestion]}"
            end
          end

          raise ValidationError, error_msg
        end

        true
      end

      # Setup and teardown helpers for validation tests
      def setup_validation_test
        # Ensure middleware is registered
        @original_middleware_state = CommandRecorder.recording?

        # Clear any existing state
        CommandRecorder.clear if CommandRecorder.recording?

        # Enable database logging for better debugging
        @original_logging_state = Familia.enable_database_logging
        Familia.enable_database_logging = true

        # Enable command counting
        @original_counter_state = Familia.enable_database_counter
        Familia.enable_database_counter = true

        DatabaseCommandCounter.reset
      end

      def teardown_validation_test
        # Stop recording if active
        CommandRecorder.stop_recording if CommandRecorder.recording?

        # Restore original states
        Familia.enable_database_logging = @original_logging_state if @original_logging_state
        Familia.enable_database_counter = @original_counter_state if @original_counter_state

        # Reset counters
        DatabaseCommandCounter.reset
      end

      # Wrapper for validation tests with automatic setup/teardown
      def with_validation_test(&block)
        setup_validation_test
        begin
          block.call
        ensure
          teardown_validation_test
        end
      end

      # Helper to create expectation builders for common patterns
      def expect_horreum_save(class_name, identifier, fields = {})
        dbkey = "#{class_name.to_s.downcase}:#{identifier}:object"

        expectations = CommandExpectations.new
        fields.each do |field, value|
          expectations.hset(dbkey, field.to_s, value.to_s)
        end

        expectations
      end

      def expect_horreum_load(class_name, identifier, fields = [])
        dbkey = "#{class_name.to_s.downcase}:#{identifier}:object"

        expectations = CommandExpectations.new
        if fields.empty?
          expectations.hgetall(dbkey)
        else
          fields.each do |field|
            expectations.hget(dbkey, field.to_s)
          end
        end

        expectations
      end

      def expect_data_type_operation(class_name, identifier, type_name, operation, *args)
        dbkey = "#{class_name.to_s.downcase}:#{identifier}:#{type_name}"

        expectations = CommandExpectations.new
        expectations.command(operation, dbkey, *args)
      end

      # Debugging helpers
      def debug_print_commands(command_sequence = nil)
        commands = command_sequence || capture_redis_commands { yield if block_given? }

        puts "Redis Commands Executed (#{commands.command_count} total):"
        puts "=" * 50

        commands.commands.each_with_index do |cmd, i|
          prefix = cmd.atomic_command? ? "[TX]" : "    "
          puts "#{prefix} #{i + 1}. #{cmd} (#{cmd.duration_us}µs)"
        end

        if commands.transaction_count > 0
          puts "\nTransactions (#{commands.transaction_count} total):"
          commands.transaction_blocks.each_with_index do |tx, i|
            puts "  #{i + 1}. #{tx.command_count} commands"
          end
        end

        puts "=" * 50
      end

      def debug_print_performance(command_sequence = nil)
        commands = command_sequence || CommandRecorder.current_sequence
        validator = Validator.new(performance_tracking: true)
        analysis = validator.analyze_performance(commands)

        puts "Performance Analysis:"
        puts "=" * 30
        puts "Total Commands: #{analysis[:total_commands]}"
        puts "Total Duration: #{analysis[:total_duration_ms].round(2)}ms"
        puts "Average Command Time: #{analysis[:average_command_time_us].round(2)}µs"
        puts "Efficiency Score: #{analysis[:efficiency_score].round(1)}/100"

        if analysis[:slowest_commands].any?
          puts "\nSlowest Commands:"
          analysis[:slowest_commands].each do |cmd|
            puts "  #{cmd[:command]} (#{cmd[:duration_us]}µs)"
          end
        end

        if analysis[:potential_n_plus_one].any?
          puts "\nPotential N+1 Patterns:"
          analysis[:potential_n_plus_one].each do |pattern|
            puts "  #{pattern[:command]}: #{pattern[:count]} calls"
          end
        end

        puts "=" * 30
      end

      # Matcher helpers for more readable tests
      def match_command(cmd, *args)
        if args.empty?
          ->(recorded) { recorded.command == cmd.to_s.upcase }
        else
          ->(recorded) { recorded.command == cmd.to_s.upcase && recorded.args == args.map(&:to_s) }
        end
      end

      def match_pattern(pattern)
        case pattern
        when Regexp
          ->(recorded) { pattern.match?(recorded.to_s) }
        when String
          ->(recorded) { recorded.to_s.include?(pattern) }
        else
          pattern
        end
      end

      def any_string
        ArgumentMatcher.new(:any_string)
      end

      def any_number
        ArgumentMatcher.new(:any_number)
      end

      def any_value
        ArgumentMatcher.new(:any_value)
      end
    end

    # Extended test helpers specifically for Familia data types
    module FamiliaTestHelpers
      include TestHelpers

      # Assert Familia object operations
      def assert_familia_save(obj, expected_fields = nil, &block)
        class_name = obj.class.name.split('::').last.downcase
        identifier = obj.identifier

        assert_redis_commands do |expect|
          if expected_fields
            expected_fields.each do |field, value|
              expect.hset("#{class_name}:#{identifier}:object", field.to_s, value.to_s)
            end
          else
            expect.match_pattern(/^HSET #{class_name}:#{identifier}:object/)
          end

          block.call if block
          obj.save
        end
      end

      def assert_familia_load(obj_class, identifier, &block)
        class_name = obj_class.name.split('::').last.downcase

        assert_redis_commands do |expect|
          expect.hgetall("#{class_name}:#{identifier}:object")

          block.call if block
          obj_class.new(id: identifier).refresh!
        end
      end

      def assert_familia_destroy(obj, &block)
        class_name = obj.class.name.split('::').last.downcase
        identifier = obj.identifier

        assert_redis_commands do |expect|
          expect.del("#{class_name}:#{identifier}:object")

          block.call if block
          obj.destroy!
        end
      end

      # Assert data type operations
      def assert_list_operation(obj, list_name, operation, *args, &block)
        class_name = obj.class.name.split('::').last.downcase
        identifier = obj.identifier
        dbkey = "#{class_name}:#{identifier}:#{list_name}"

        assert_redis_commands do |expect|
          expect.command(operation.to_s.upcase, dbkey, *args)

          block.call if block
          obj.send(list_name).send(operation, *args)
        end
      end

      def assert_set_operation(obj, set_name, operation, *args, &block)
        class_name = obj.class.name.split('::').last.downcase
        identifier = obj.identifier
        dbkey = "#{class_name}:#{identifier}:#{set_name}"

        assert_redis_commands do |expect|
          expect.command(operation.to_s.upcase, dbkey, *args)

          block.call if block
          obj.send(set_name).send(operation, *args)
        end
      end

      def assert_sorted_set_operation(obj, zset_name, operation, *args, &block)
        class_name = obj.class.name.split('::').last.downcase
        identifier = obj.identifier
        dbkey = "#{class_name}:#{identifier}:#{zset_name}"

        assert_redis_commands do |expect|
          expect.command(operation.to_s.upcase, dbkey, *args)

          block.call if block
          obj.send(zset_name).send(operation, *args)
        end
      end
    end
  end
end
