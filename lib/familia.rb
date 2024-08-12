# rubocop:disable all
# frozen_string_literal: true

require 'redis'
require 'uri/redis'

require_relative 'familia/errors'
require_relative 'familia/version'
require_relative 'familia/logging'
require_relative 'familia/connection'
require_relative 'familia/settings'
require_relative 'familia/utils'

require_relative 'familia/core_ext'

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

  @debug = true
  @members = []

  class << self
    attr_accessor :debug
    attr_reader :members

    def included(member)
      raise Problem, "#{member} should subclass Familia::Horreum"
    end
  end

  extend Logging
  extend Connection
  extend Settings
  extend Utils
end

require_relative 'familia/redistype'
require_relative 'familia/horreum'
