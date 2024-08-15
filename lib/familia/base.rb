# frozen_string_literal: true

#
module Familia
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
  module Base
    @features = nil
    @dump_method = :to_json
    @load_method = :from_json

    class << self
      attr_reader :features
      attr_accessor :dump_method, :load_method

      def add_feature(klass, methname)
        @features ||= {}
        Familia.ld "[#{self}] Adding feature #{klass} as #{methname}"

        features[methname] = klass
      end
    end
  end
end
