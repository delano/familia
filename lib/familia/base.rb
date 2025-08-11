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
    @features_available = nil
    @feature_definitions = nil
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
      attr_reader :features_available, :feature_definitions
      attr_accessor :dump_method, :load_method

      def add_feature(klass, feature_name, depends_on: [])
        @features_available ||= {}
        Familia.trace :ADD_FEATURE, klass, feature_name, caller(1..1) if Familia.debug?

        # Create field definition object
        feature_def = FeatureDefinition.new(
          name: feature_name,
          depends_on: depends_on,
        )

        # Track field definitions after defining field methods
        @feature_definitions ||= {}
        @feature_definitions[feature_name] = feature_def

        features_available[feature_name] = klass
      end
    end

    def generate_id
      @identifier ||= Familia.generate_id # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def uuid
      @uuid ||= SecureRandom.uuid
    end
  end
end
