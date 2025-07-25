# try/features/quantization_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test quantization feature functionality

# Define a test class with quantization feature
class QuantizedTest < Familia::Horreum
  feature :quantization
  identifier_field :id
  field :id
  field :data
  default_expiration 300 # 5 minutes for testing
end

## Class has qstamp method from feature
QuantizedTest.respond_to?(:qstamp)
#=> true

## Object has qstamp method from feature
@test_obj = QuantizedTest.new
@test_obj.respond_to?(:qstamp)
#=> true

## Familia has global qstamp method
Familia.respond_to?(:qstamp)
#=> true

## Familia has now method for current time
Familia.respond_to?(:now)
#=> true

## Can get current time with Familia.now
now = Familia.now
now.class
#=> Float

## qstamp with no arguments returns current quantized timestamp
stamp1 = QuantizedTest.qstamp
p [:QuantizedTest, QuantizedTest.qstamp]
stamp1.class
#=> Integer

## qstamp with quantum returns quantized timestamp
stamp2 = QuantizedTest.qstamp(3600) # 1 hour quantum
stamp2.class
#=> Integer

## qstamp with quantum and pattern returns formatted string
stamp3 = QuantizedTest.qstamp(3600, pattern: '%Y%m%d%H')
stamp3.class
#=> String

## qstamp with time argument
stamp4 = QuantizedTest.qstamp(3600, pattern: '%Y%m%d%H', time: Time.new(2023, 6, 15, 14, 30, 0))
stamp4.class
#=> String

## Object qstamp works same as class method
obj_stamp = @test_obj.qstamp(3600)
obj_stamp.class
#=> Integer

## Different quantum values produce different buckets
test_time = Time.utc(2023, 6, 15, 14, 30, 0) # use a fixed time, mid-day (avoid ToD boundary)
@hour_stamp = QuantizedTest.qstamp(3600, time: test_time)
@day_stamp = QuantizedTest.qstamp(86_400, time: test_time)
#=> 1686787200
#=<> @hour_stamp
#==> @hour_stamp == 1686837600

## Pattern formatting works correctly
time_str = QuantizedTest.qstamp(3600, pattern: '%Y-%m-%d %H:00:00')
time_str.match?(/\d{4}-\d{2}-\d{2} \d{2}:00:00/)
#=> true

## Can pass custom time to qstamp
test_time = Time.utc(2023, 6, 15, 14, 30, 1)
# NOTE: _Not_  Time.new(2023, 6, 15, 14, 30, 1).utc which is the current time
# locally where this code is running, then converted to UTC.
custom_stamp = QuantizedTest.qstamp(3600, pattern: '%Y%m%d%H', time: test_time)
custom_stamp
#=> "2023061514"

# Cleanup
@test_obj.id = 'quantized_test_obj' # Set identifier before cleanup
@test_obj.destroy! if @test_obj
