# rubocop:disable all
# frozen_string_literal: true

require 'redis'
require 'uri/redis'

require_relative 'familia/core_ext'

require_relative 'familia/errors'
require_relative 'familia/version'

# Familia - A family warehouse for Redis
#
# Familia provides a way to organize and store Ruby objects in Redis.
# It includes various modules and classes to facilitate object-Redis interactions.
#
# @example Basic usage
#   class Flower < Familia::Horreum
#
#     indentifer :my_identifier_method
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

  @debug = false
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
    #    config.enable_redis_logging = true
    #  end
    #
    #
    def configure
      yield self
    end
  end

  require_relative 'familia/logging'
  require_relative 'familia/connection'
  require_relative 'familia/settings'
  require_relative 'familia/utils'

  extend Logging
  extend Connection
  extend Settings
  extend Utils
end

# A common module for Familia::RedisType and Familia::Horreum to include.
#
# This allows us to use a single comparison to check if a class is a
# Familia class. e.g.
#
#     klass.include?(Familia::Base) # => true
#     klass.ancestors.member?(Familia::Base) # => true
#
# @see Familia::Horreum
# @see Familia::RedisType
#
module Familia::Base; end

require_relative 'familia/redistype'
require_relative 'familia/horreum'
