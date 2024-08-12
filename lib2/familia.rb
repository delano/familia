# rubocop:disable all
# frozen_string_literal: true

require 'redis'
require 'uri/redis'

require_relative 'familia/errors'
require_relative 'familia/logging'
require_relative 'familia/connection'
require_relative 'familia/settings'
require_relative 'familia/utils'

require_relative 'familia/core_ext'

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

require_relative 'familia/redisobject'
require_relative 'familia/horreum'
