# rubocop:disable all
# frozen_string_literal: true

require 'securerandom'

require 'uri/redis'
require 'gibbler'

require_relative 'familia/errors'
require_relative 'familia/logging'
require_relative 'familia/utils'

module Familia
  include Gibbler::Complex

  extend Logging
  extend Utils

  @uri = URI.parse 'redis://127.0.0.1'
  @debug = true
  @delim = ':'
  @suffix = :object

  class << self
    attr_accessor :uri, :debug, :delim, :suffix
    attr_reader :members

    def included(base)
      Familia.ld "[Familia] including #{base}"
      base.extend(ClassMethods)
      base.extend(Familia::Horreum::ClassMethods)
      base.include(Familia::Horreum::InstanceMethods)

      # Tracks all the classes/modules that include Familia. It's
      # 10pm, do you know where you Familia members are?
      @members ||= []
      @members << base
    end

    # We define this do-nothing method because it reads better
    # than simply Familia.suffix in some contexts.
    def default_suffix
      suffix
    end
  end

  module ClassMethods

    def identifier(val = nil)
      @identifier = val if val
      @identifier
    end

    def field(name)
      @fields ||= []
      @fields << name
      attr_accessor name
    end

    def fields
      @fields ||= []
      @fields
    end

    def generate_id
      input = SecureRandom.hex(32)  # 16=128 bits, 32=256 bits
      # Not using gibbler to make sure it's always SHA256
      Digest::SHA256.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
    end
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
