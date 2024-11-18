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
        Familia.ld "[#{self}] Adding feature #{klass} as #{methname.inspect}"

        features[methname] = klass
      end
    end

    # Base implementation of update_expiration that maintains API compatibility
    # with the :expiration feature's implementation.
    #
    # This is a no-op implementation that gets overridden by features like
    # :expiration. It accepts an optional ttl parameter to maintain interface
    # compatibility with the overriding implementations.
    #
    # @param ttl [Integer, nil] Time To Live in seconds (ignored in base implementation)
    # @return [nil] Always returns nil
    #
    # @note This is a no-op implementation. Classes that need expiration
    #       functionality should include the :expiration feature.
    #
    def update_expiration(ttl: nil)
      Familia.ld "[update_expiration] Method not defined for #{self.class}. Key: #{rediskey} (caller: #{caller(1..1)})"
      nil
    end

    def generate_id
      @key ||= Familia.generate_id
      @key
    end

    def uuid
      @uuid ||= SecureRandom.uuid
      @uuid
    end
  end
end
