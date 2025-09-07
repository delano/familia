# lib/familia.rb

require 'oj'
require 'redis'
require 'uri/valkey'
require 'connection_pool'

# Configure OJ defaults for Familia
Oj.default_options = {
  mode: :compat,           # Compatibility mode respects to_json methods
  symbol_keys: false,      # Default to string keys
  bigdecimal_as_decimal: false,
  create_additions: false, # Don't allow arbitrary class creation
  second_precision: 6      # Match JSON gem precision
}

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
  end

  require_relative 'familia/secure_identifier'
  require_relative 'familia/logging'
  require_relative 'familia/connection'
  require_relative 'familia/settings'
  require_relative 'familia/utils'
  require_relative 'familia/json_serializer'

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

# Backwards compatibility for tests and examples that use JSON directly
# This allows existing code to continue working while we use Familia::JsonSerializer internally
unless defined?(JSON)
  JSON = Familia::JsonSerializer

  # Add to_json methods to core classes for compatibility
  class Object
    def to_json(*args)
      Familia::JsonSerializer.dump(self)
    end
  end

  class Hash
    def to_json(*args)
      Familia::JsonSerializer.dump(self)
    end
  end

  class Array
    def to_json(*args)
      Familia::JsonSerializer.dump(self)
    end
  end

  class String
    def to_json(*args)
      Familia::JsonSerializer.dump(self)
    end
  end

  class Numeric
    def to_json(*args)
      Familia::JsonSerializer.dump(self)
    end
  end

  class TrueClass
    def to_json(*args)
      Familia::JsonSerializer.dump(self)
    end
  end

  class FalseClass
    def to_json(*args)
      Familia::JsonSerializer.dump(self)
    end
  end

  class NilClass
    def to_json(*args)
      Familia::JsonSerializer.dump(self)
    end
  end
end
