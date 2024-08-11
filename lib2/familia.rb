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

  def self.included(base)
    base.extend(ClassMethods)
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
  end

  def initialize
  end

  def identifier
    send(self.class.identifier)
  end

  def to_h
  end

  def to_a
  end

  def join(*args)
    Familia.join(args.map { |field| send(field) }))
  end

  extend Logging
  extend Utils
end
