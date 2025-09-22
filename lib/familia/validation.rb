# lib/familia/validation.rb

# Valkey/Redis Command Validation Framework for Familia
#
# Provides comprehensive validation of db operations to ensure commands
# execute exactly as expected, with particular focus on atomicity verification
# for transaction-based operations.
#
# @example Basic command validation
#   include Familia::Validation
#
#   validator = Validator.new
#   result = validator.validate do |expect|
#     expect.hset("user:123", "name", "John")
#           .incr("counter")
#
#     # Execute code that should perform these operations
#     user = User.new(id: "123", name: "John")
#     user.save
#     Counter.increment
#   end
#
#   puts result.valid? ? "PASS" : "FAIL"
#
# @example Using test helpers in try files
#   require_relative 'lib/familia/validation'
#   extend Familia::Validation::TestHelpers
#
#   ## User save executes expected Valkey/Redis commands
#   user = TestUser.new(id: "123", name: "John")
#   assert_database_commands do |expect|
#     expect.hset("testuser:123:object", "name", "John")
#     user.save
#   end
#   #=> true
#
# @example Transaction atomicity validation
#   extend Familia::Validation::TestHelpers
#
#   ## Transfer should be atomic
#   assert_atomic_operation do |expect|
#     expect.transaction do |tx|
#       tx.hset("account:123", "balance", "500")
#         .hset("account:456", "balance", "1500")
#     end
#
#     transfer_funds(from: "123", to: "456", amount: 500)
#   end
#   #=> true

require_relative 'validation/command_recorder'
require_relative 'validation/expectations'
require_relative 'validation/validator'
require_relative 'validation/validation_helpers'

module Familia
  module Validation
    # Quick access to main validator
    def self.validator(options = {})
      Validator.new(options)
    end

    # Validate a block of code against expected Valkey/Redis commands
    def self.validate(options = {}, &block)
      validator(options).validate(&block)
    end

    # Validate that code executes atomically
    def self.validate_atomicity(options = {}, &block)
      validator(options).validate_atomicity(&block)
    end

    # Capture Valkey/Redis commands without validation
    def self.capture_commands(&block)
      CommandRecorder.start_recording
      block.call if block_given?
      CommandRecorder.stop_recording
    end

    # Quick performance analysis
    def self.analyze_performance(&block)
      commands = capture_commands(&block)
      PerformanceAnalyzer.new(commands).analyze
    end

    # Register validation middleware with Valkey/Redis client
    def self.register_middleware!
      if defined?(RedisClient)
        RedisClient.register(CommandRecorder::Middleware)
      else
        warn "RedisClient not available - command recording will not work"
      end
    end

    # Configuration for validation framework
    module Config
      # Default options for validators
      DEFAULT_OPTIONS = {
        auto_register_middleware: true,
        strict_atomicity: true,
        performance_tracking: true,
        command_filtering: :all
      }.freeze

      @options = DEFAULT_OPTIONS.dup

      class << self
        attr_accessor :options

        def configure
          yield self if block_given?
        end

        def reset!
          @options = DEFAULT_OPTIONS.dup
        end

        # Option accessors
        def auto_register_middleware?
          @options[:auto_register_middleware]
        end

        def strict_atomicity?
          @options[:strict_atomicity]
        end

        def performance_tracking?
          @options[:performance_tracking]
        end

        def command_filtering
          @options[:command_filtering]
        end
      end
    end
  end
end

# Auto-register middleware if enabled
Familia::Validation.register_middleware! if Familia::Validation::Config.auto_register_middleware?
