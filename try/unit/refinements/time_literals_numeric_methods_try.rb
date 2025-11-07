# try/unit/refinements/time_literals_numeric_methods_try.rb
#
# frozen_string_literal: true

# try/refinements/time_literals_numeric_methods_try.rb

require_relative '../../support/helpers/test_helpers'

class TestNumericWithTimeLiterals
  include Familia::Refinements::TimeLiterals::NumericMethods

  def initialize(value)
    @value = value
  end

  def to_f
    @value.to_f
  end

  def to_i
    @value.to_i
  end

  def positive?
    @value.positive?
  end

  def zero?
    @value.zero?
  end

  def abs
    @value.abs
  end

  def <(other)
    @value < other
  end

  def >(other)
    @value > other
  end

  def -(other)
    @value - other
  end

  def +(other)
    @value + other
  end

  def *(other)
    @value * other
  end

  def /(other)
    @value / other
  end
end

## Can create numeric with time literal methods
test_num = TestNumericWithTimeLiterals.new(5)
test_num.respond_to?(:minutes)
#=> true
#=:> TrueClass

## Basic time unit conversions work
test_num = TestNumericWithTimeLiterals.new(5)
test_num.minutes
#=> 300.0
#=:> Float

## Minutes conversion
test_num = TestNumericWithTimeLiterals.new(2)
test_num.minutes
#=> 120.0
#=:> Float

## Hours conversion
test_num = TestNumericWithTimeLiterals.new(2)
test_num.hours
#=> 7200.0
#=:> Float

## Days conversion
test_num = TestNumericWithTimeLiterals.new(1)
test_num.days
#=> 86400.0
#=:> Float

## Conversion from seconds to other units
test_num = TestNumericWithTimeLiterals.new(3600)
test_num.in_hours
#=> 1.0
#=:> Float

## Conversion from seconds to days
test_num = TestNumericWithTimeLiterals.new(86400)
test_num.in_days
#=> 1.0
#=:> Float

## to_ms conversion
test_num = TestNumericWithTimeLiterals.new(5)
test_num.to_ms
#=> 5000.0
#=:> Float

## humanize for seconds
test_num = TestNumericWithTimeLiterals.new(30)
test_num.humanize
#=> "30 seconds"
#=:> String

## humanize for minutes
test_num = TestNumericWithTimeLiterals.new(120)
test_num.humanize
#=> "2 minutes"
#=:> String

## to_bytes conversion
test_num = TestNumericWithTimeLiterals.new(1024)
test_num.to_bytes
#=> "1.00 KiB"
#=:> String

## age_in with days
old_time = Familia.now.to_f - 86400
test_num = TestNumericWithTimeLiterals.new(old_time)
age = test_num.age_in(:days)
age.round
#=> 1
#=:> Integer

## older_than? check
old_timestamp = TestNumericWithTimeLiterals.new(Familia.now.to_f - 7200) # 2 hours ago
old_timestamp.older_than?(3600) # 1 hour
#=> true
#=:> TrueClass

## within? check for recent timestamp
recent_timestamp = TestNumericWithTimeLiterals.new(Familia.now.to_f - 30) # 30 seconds ago
recent_timestamp.within?(60) # within 1 minute
#=> true
#=:> TrueClass
