# try/core/utils_try.rb

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Test Familia utility methods and helpers

##
## Key helpers
##
Familia.delim(':') # Ensure default

## Can join values with delimiter
result = Familia.join('user', '123', 'sessions')
result
#=> "user:123:sessions"

## Can join with custom delimiter
original_delim = Familia.delim
Familia.delim('|')
result = Familia.join('a', 'b', 'c')
[result, Familia.delim]
#=> ["a|b|c", "|"]

## Can split values with custom delimiter
parts = Familia.split('a|b|c')
parts
#=> ["a", "b", "c"]

## Resets delimiter for remaining tests
Familia.delim(':')
#=> ":"

## Can split with default delimiter after reset
parts = Familia.split('user:123:data')
parts
#=> ["user", "123", "data"]

## Can create dbkey with default delimiter
key = Familia.dbkey('v1', 'customer', 'email')
key
#=> "v1:customer:email"

##
## Other Utilities
##

## qstamp returns integer timestamp by default
stamp = Familia.qstamp
stamp.class
#=> Integer

## qstamp with pattern returns formatted string
formatted = Familia.qstamp(3600, pattern: '%Y%m%d%H')
[formatted.class, formatted.length == 10]
#=> [String, true]

## qstamp works with custom time
test_time = Time.utc(2023, 6, 15, 14, 30, 0)
custom_stamp = Familia.qstamp(3600, time: test_time)
Time.at(custom_stamp).utc.hour
#=> 14

## identifier_extractor extracts class names
test_class = Class.new(Familia::Horreum)
test_class.define_singleton_method(:name) { 'TestClass' }
Familia.identifier_extractor(test_class)
#=> "TestClass"

## identifier_extractor extracts identifiers from Familia objects
customer_class = Class.new(Familia::Horreum) do
  identifier_field :custid
  field :custid
end
customer = customer_class.new(custid: 'customer_123')
Familia.identifier_extractor(customer)
#=> "customer_123"

## identifier_extractor raises error for non-Familia objects
begin
  Familia.identifier_extractor({ key: 'value' })
rescue Familia::NotDistinguishableError => e
  e.class
end
#=> Familia::NotDistinguishableError

##
## Time utilities
##

## now returns Float timestamp in seconds
time_result = Familia.now
[time_result.is_a?(Float), time_result > 0]
#=> [true, true]

## now accepts Time argument
test_time = Time.utc(2023, 6, 15, 14, 30, 0)
result_time = Familia.now(test_time)
[result_time.is_a?(Float), result_time == test_time.utc.to_f]
#=> [true, true]

## now_in_μs returns Integer microseconds
μs_result = Familia.now_in_μs
[μs_result.is_a?(Integer), μs_result > 0]
#=> [true, true]

## now_in_microseconds is an alias for now_in_μs
alias_result = Familia.now_in_microseconds
[alias_result.is_a?(Integer), alias_result > 0]
#=> [true, true]

## now_in_μs returns monotonic time suitable for duration measurement
start = Familia.now_in_μs
sleep 0.001  # Sleep for at least 1ms
finish = Familia.now_in_μs
duration = finish - start
[duration.is_a?(Integer), duration >= 1000]  # At least 1000 microseconds (1ms)
#=> [true, true]

# Cleanup - restore defaults, leave nothing but footprints
Familia.delim(':')
Familia.suffix(:object)
Familia.default_expiration(0)
Familia.logical_database(nil)
Familia.prefix(nil)
