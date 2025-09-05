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

    using Familia::Refinements::TimeUtils

    @features_available = nil
    @feature_definitions = nil
    @dump_method = :to_json
    @load_method = :from_json

    def self.included(base)
      # Ensure the including class gets its own feature registry
      base.extend(ClassMethods)
    end

    # Familia::Base::ClassMethods
    #
    module ClassMethods
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

      # Find a feature by name, traversing this class's ancestry chain
      def find_feature(feature_name)
        Familia::Base.find_feature(feature_name, self)
      end
    end

    # Returns a string representation of the object. Implementing classes
    # are welcome to override this method to provide a more meaningful
    # representation. Using this as a default via super is recommended.
    #
    # @return [String] A string representation of the object. Never nil.
    #
    def to_s
      "#<#{self.class}:0x#{object_id.to_s(16)}>"
    end

    # Module-level methods for Familia::Base itself
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

      # Find a feature by name, traversing the ancestry chain of classes
      # that include Familia::Base
      def find_feature(feature_name, starting_class = self)
        # Convert to symbol for consistent lookup
        feature_name = feature_name.to_sym

        # Walk up the ancestry chain, checking each class that includes Familia::Base
        starting_class.ancestors.each do |ancestor|
          next unless ancestor.respond_to?(:features_available)
          next unless ancestor.features_available

          if ancestor.features_available.key?(feature_name)
            return ancestor.features_available[feature_name]
          end
        end

        nil
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
