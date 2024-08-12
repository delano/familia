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

  extend Logging
  extend Connection
  extend Settings
  extend Utils

  @debug = true

  @members = []

  class << self
    attr_accessor :debug
    attr_reader :members

    def included(member)
      Familia.ld "[Familia] including #{member}"
      member.extend(Familia::Horreum::ClassMethods)
      member.include(Familia::Horreum::InstanceMethods)

      # Tracks all the classes/modules that include Familia. It's
      # 10pm, do you know where you Familia members are?
      @members << member
    end

  end

  module ClassMethods

  end

  def initialize *args, **kwargs
    Familia.ld "[Horreum] Initializing #{self.class} with #{args.inspect} and #{kwargs.inspect}"
    initialize_redis_objects
  end

  def identifier
    send(self.class.identifier)
  end

  def to_h
  end

  def to_a
  end

  def join(*args)
    Familia.join(args.map { |field| send(field) })
  end

end

require_relative 'familia/redisobject'
require_relative 'familia/class_methods'
require_relative 'familia/instance_methods'
