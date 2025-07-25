# lib/familia/base.rb

#
module Familia
  # A common module for Familia::DataType and Familia::Horreum to include.
  #
  # This allows us to use a single comparison to check if a class is a
  # Familia class. e.g.
  #
  #     klass.include?(Familia::Base) # => true
  #     klass.ancestors.member?(Familia::Base) # => true
  #
  # @see Familia::Horreum
  # @see Familia::DataType
  #
  module Base
    @features = nil
    @dump_method = :to_json
    @load_method = :from_json

    # Returns a string representation of the object. Implementing classes
    # are welcome to override this method to provide a more meaningful
    # representation. Using this as a default via super is recommended.
    #
    # @return [String] A string representation of the object. Never nil.
    #
    def to_s
      "#<#{self.class}:0x#{object_id.to_s(16)}>"
    end

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
    # :expiration. It accepts an optional default_expiration parameter to maintain interface
    # compatibility with the overriding implementations.
    #
    # @param default_expiration [Integer, nil] Time To Live in seconds (ignored in base implementation)
    # @return [nil] Always returns nil
    #
    # @note This is a no-op implementation. Classes that need expiration
    #       functionality should include the :expiration feature.
    #
    def update_expiration(default_expiration: nil)
      Familia.ld "[update_expiration] Feature not enabled for #{self.class}. Key: #{dbkey} (caller: #{caller(1..1)})"
      nil
    end

    def generate_id
      @identifier ||= Familia.generate_id
      @identifier
    end

    def uuid
      @uuid ||= SecureRandom.uuid
      @uuid
    end
  end
end
