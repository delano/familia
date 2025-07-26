# lib/familia.rb

require 'json'
require 'redis'
require 'uri/valkey'
require 'connection_pool'

require_relative 'familia/core_ext'
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

  extend SecureIdentifier
  extend Logging
  extend Connection
  extend Settings
  extend Utils
end

require_relative 'familia/base'
require_relative 'familia/features'
require_relative 'familia/datatype'
require_relative 'familia/horreum'
