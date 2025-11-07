# lib/familia/data_type/types/counter.rb
#
# frozen_string_literal: true

module Familia
  class Counter < StringKey
    def initialize(*args)
      super
      @opts[:default] ||= 0
    end

    # Enhanced counter semantics
    def reset(val = 0)
      set(val).to_s.eql?('OK')
    end

    def increment_if_less_than(threshold, amount = 1)
      current = to_i
      return false if current >= threshold

      incrementby(amount)
      true
    end

    def atomic_increment_and_get(amount = 1)
      incrementby(amount)
    end

    # Override to ensure integer serialization
    def value=(val)
      super(val.to_i)
    end

    def value
      super.to_i
    end
  end
end

Familia::DataType.register Familia::Counter, :counter
