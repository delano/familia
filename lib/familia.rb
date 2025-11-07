# lib/familia.rb

require 'oj'
require 'redis'
require 'uri/valkey'
require 'connection_pool'
require 'concurrent-ruby'

# OJ configuration is handled internally by Familia::JsonSerializer

require_relative 'multi_result'
require_relative 'familia/refinements'
require_relative 'familia/errors'
require_relative 'familia/version'
require_relative 'familia/thread_safety/monitor'
require_relative 'familia/thread_safety/instrumented_mutex'

# Familia - A family warehouse for Valkey/Redis
#
# Familia provides a way to organize and store Ruby objects in the database.
# It includes various modules and classes to facilitate object-Database interactions.
#
# @example Basic usage
#   class Flower < Familia::Horreum
#
#     identifier_field :my_identifier_method
#     field  :token
#     field  :name
#     list   :owners
#     set    :tags
#     zset   :metrics
#     hash   :props
#     string :value, :default => "GREAT!"
#   end
#
# @see https://github.com/delano/familia
#
module Familia
  @debug = ENV['FAMILIA_DEBUG'].to_s.downcase.match?(/^(true|1)$/i).freeze
  @members = []

  using Refinements::StylizeWords

  class << self
    attr_writer :debug
    attr_reader :members

    # Thread safety monitoring controls
    def thread_safety_monitor
      ThreadSafety::Monitor.instance
    end

    def start_monitoring!
      thread_safety_monitor.start!
    end

    def stop_monitoring!
      thread_safety_monitor.stop!
    end

    def thread_safety_report
      thread_safety_monitor.report
    end

    def thread_safety_metrics
      thread_safety_monitor.export_metrics
    end

    def included(member)
      raise Problem, "#{member} should subclass Familia::Horreum"
    end

    def resolve_class(target)
      case target
      when Class
        target
      when ::String, Symbol
        config_name = target.to_s.demodularize.snake_case
        member_by_config_name(config_name)
      else
        raise ArgumentError, "Expected Class, String, or Symbol, got #{target.class}"
      end
    end

    # A convenience pattern for configuring Familia.
    #
    # @example
    #  Familia.configure do |config|
    #    config.debug = true
    #    config.enable_database_logging = true
    #  end
    #
    #
    def configure
      yield self
    end

    # Checks if debug mode is enabled
    #
    # e.g. Familia.debug = true
    #
    # @return [Boolean] true if debug mode is on, false otherwise
    def debug?
      @debug == true
    end

    # Remove a member class from the members array.
    # Used for test cleanup to prevent anonymous classes from polluting
    # the global registry.
    #
    # @param klass [Class] The class to remove from members
    # @return [Class, nil] The removed class or nil if not found
    def unload_member(klass)
      Familia.debug "[unload_member] Removing #{klass} from members"
      @members.delete(klass)
    end

    # Remove all anonymous/test classes from members array.
    # Anonymous classes have nil names, which cause issues in member_by_config_name.
    #
    # @return [Array<Class>] The removed anonymous classes
    def clear_anonymous_members
      anonymous_classes = @members.select { |m| m.name.nil? }
      Familia.debug "[clear_anonymous_members] Removing #{anonymous_classes.size} anonymous classes"
      @members.reject! { |m| m.name.nil? }
      anonymous_classes
    end

    # Check if we're in test mode by looking for test-related constants
    # or environment variables
    #
    # @return [Boolean] true if running in test mode
    def test_mode?
      defined?(Tryouts) || ENV['FAMILIA_TEST_MODE'] == 'true'
    end

    private

    # Finds a member class by its symbolized name
    #
    # NOTE: If you are not getting the expected results, check the load order of
    # the models. The one your looking for may not be loaded yet. Currently
    # models are loaded naively -- that is, they are loaded in the order
    # they are defined in the codebase.
    #
    # @param config_name [Symbol, String] The symbolized name of the member class
    # @return [Class, nil] The member class if found, nil otherwise
    #
    # @example
    #   Familia.member_by_config_name(:flower) # => Flower class
    #   Familia.member_by_config_name('flower') # => Flower class
    #   Familia.member_by_config_name(:nonexistent) # => nil
    #
    def member_by_config_name(config_name)
      Familia.debug "[member_by_config_name] #{members.map(&:config_name)} #{config_name}"

      members.find { |m| m.config_name.to_s.eql?(config_name.to_s) }
    end
  end

  require_relative 'familia/secure_identifier'
  require_relative 'familia/logging'
  require_relative 'familia/connection'
  require_relative 'familia/settings'
  require_relative 'familia/utils'
  require_relative 'familia/identifier_extractor'
  require_relative 'familia/json_serializer'

  extend SecureIdentifier
  extend Connection
  extend Settings
  extend Logging
  extend Utils
end

require_relative 'familia/instrumentation'
require_relative 'familia/base'
require_relative 'familia/features'
require_relative 'familia/data_type'
require_relative 'familia/horreum'
require_relative 'familia/encryption'
