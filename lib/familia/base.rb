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

    using Familia::Refinements::TimeLiterals

    @feature_definitions = nil
    @dump_method = :to_json
    @load_method = :from_json

    def self.included(base)
      # Ensure the including class gets its own methods
      base.extend(ClassMethods)
    end

    # Familia::Base::ClassMethods
    #
    module ClassMethods
      attr_reader :feature_definitions
      attr_accessor :dump_method, :load_method
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
      attr_reader :feature_definitions
      attr_accessor :dump_method, :load_method
    end

    def generate_id
      @identifier ||= Familia.generate_id # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def uuid
      @uuid ||= SecureRandom.uuid
    end
  end
end
