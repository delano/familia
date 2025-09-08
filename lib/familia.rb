# lib/familia.rb

require 'json'
require 'redis'
require 'uri/valkey'
require 'connection_pool'

require_relative 'familia/refinements'
require_relative 'familia/errors'
require_relative 'familia/version'

# Familia - A family warehouse for Redis
#
# Familia provides a way to organize and store Ruby objects in Redis.
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

  class << self
    attr_accessor :debug
    attr_reader :members

    def included(member)
      raise Problem, "#{member} should subclass Familia::Horreum"
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

    # Adds a member class to the list of tracked members
    #
    # @param member [Module, Class] The class to add
    def add_member(member)
      @members << member
    end

    # Unloads a member class by removing its constant
    #
    # @param member [Module, Class, String, Symbol] The class or class name to unload
    def unload_member(member)
      case member
      when String, Symbol
        member_name = member.to_s
        # Find the actual class object in members for removal
        class_member = @members.find { |m| m.respond_to?(:name) && m.name == member_name }
      else
        member_name = member.name
        class_member = member
      end

      # For namespaced constants like Nested::CustomClass, we need to:
      # 1. Find the actual parent module (Nested, not Object)
      # 2. Use only the simple name (CustomClass, not Nested::CustomClass)
      name_parts = member_name.split('::')
      simple_name = name_parts.last

      if name_parts.length > 1
        # Navigate to the actual parent module
        parent_module = name_parts[0..-2].reduce(Object) { |mod, part| mod.const_get(part) }
      else
        parent_module = Object
      end

      Familia.ld "[#{member_name}] Unloading '#{simple_name}' from #{parent_module}"

      # Only remove the constant if it exists
      if parent_module.const_defined?(simple_name.to_sym, false)
        parent_module.send(:remove_const, simple_name.to_sym)
      end

      # Remove from members list (remove the class object, not string)
      @members.delete(class_member) if class_member
    end

    # Unloads all tracked member classes
    #
    # Iterates through all members and calls unload_member for each one
    def unload!
      # Create a copy to avoid modifying array during iteration
      members_to_unload = @members.dup
      members_to_unload.each { |member| unload_member(member) }
    end
  end

  require_relative 'familia/secure_identifier'
  require_relative 'familia/logging'
  require_relative 'familia/connection'
  require_relative 'familia/settings'
  require_relative 'familia/utils'

  extend SecureIdentifier
  extend Connection
  extend Settings
  extend Logging
  extend Utils
end

require_relative 'familia/base'
require_relative 'familia/features/autoloadable'
require_relative 'familia/features'
require_relative 'familia/data_type'
require_relative 'familia/horreum'
require_relative 'familia/encryption'
