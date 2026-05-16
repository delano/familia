# frozen_string_literal: true

module Familia
  class DataType
    # ScalarBase - Base module for non-iterable DataType classes
    #
    # Scalar types represent single values in Redis (STRING, counters, locks).
    # They do not include Enumerable because iteration over a single value
    # is not semantically meaningful.
    #
    # @example Scalar types
    #   StringKey  - Redis STRING
    #   Counter    - Redis STRING with INCR/DECR
    #   Lock       - Redis STRING with SETNX semantics
    #
    module ScalarBase
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def scalar_type?
          # Check ancestors to handle inheritance (Counter < StringKey)
          ancestors.include?(Familia::DataType::ScalarBase)
        end
      end

      def scalar_type?
        self.class.scalar_type?
      end
    end
  end
end
