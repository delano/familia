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

    # Yo, this class is like that one friend who never checks expiration dates.
    # It's living life on the edge, data-style!
    #
    # @param ttl [Integer, nil] Time To Live? More like Time To Laugh! This param
    #   is here for compatibility, but it's as useful as a chocolate teapot.
    #
    # @return [nil] Always returns nil. It's consistent in its laziness!
    #
    # @example Trying to teach an old dog new tricks
    #   immortal_data.update_expiration(86400) # Nice try, but this data is here to stay!
    #
    # @note This method is a no-op. It's like shouting into the void, but less echo-y.
    #
    def update_expiration(_ = nil)
      Familia.info "[update_expiration] Skipped for #{rediskey}. #{self.class} data is immortal!"
      nil
    end
  end
end
