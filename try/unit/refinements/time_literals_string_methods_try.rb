# try/refinements/time_literals_string_methods_try.rb

require_relative '../../support/helpers/test_helpers'

class TestStringWithTimeLiterals < String
  include Familia::Refinements::TimeLiterals::StringMethods
end

## Can create string with time literal methods
test_str = TestStringWithTimeLiterals.new("5m")
test_str.respond_to?(:in_seconds)
#=> true
#=:> TrueClass

## Parse minutes to seconds
test_str = TestStringWithTimeLiterals.new("5m")
test_str.in_seconds
#=> 300.0
#=:> Float

## Parse hours to seconds
test_str = TestStringWithTimeLiterals.new("2h")
test_str.in_seconds
#=> 7200.0
#=:> Float

## Parse days to seconds
test_str = TestStringWithTimeLiterals.new("1d")
test_str.in_seconds
#=> 86400.0
#=:> Float

## Parse decimal values
test_str = TestStringWithTimeLiterals.new("2.5h")
test_str.in_seconds
#=> 9000.0
#=:> Float

## Parse years to seconds
test_str = TestStringWithTimeLiterals.new("1y")
result = test_str.in_seconds
result > 31_000_000 && result < 32_000_000
#=> true
#=:> TrueClass

## Parse microseconds
test_str = TestStringWithTimeLiterals.new("500μs")
test_str.in_seconds
#=> 0.0005
#=:> Float

## Parse milliseconds
test_str = TestStringWithTimeLiterals.new("500ms")
test_str.in_seconds
#=> 0.5
#=:> Float

## Parse weeks
test_str = TestStringWithTimeLiterals.new("2w")
test_str.in_seconds
#=> 1209600.0
#=:> Float

## Default unit is seconds when no unit specified
test_str = TestStringWithTimeLiterals.new("30")
test_str.in_seconds
#=> 30.0
#=:> Float

## Invalid format returns nil
test_str = TestStringWithTimeLiterals.new("invalid")
test_str.in_seconds
#=> nil
#=:> NilClass

## Empty string returns nil
test_str = TestStringWithTimeLiterals.new("")
test_str.in_seconds
#=> nil
#=:> NilClass
