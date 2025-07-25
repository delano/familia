# try/core/utils_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test Familia utility methods and helpers

##
## ID Generation
##

## Familia.generate_id
Familia.respond_to?(:generate_id)
#=> true

## Can generate a default base-36 ID
id = Familia.generate_id
[id.class, id.length > 10, id.match?(/^[a-z0-9]+$/)]
#=> [String, true, true]

## Generated IDs are unique
[Familia.generate_id == Familia.generate_id]
#=> [false]

## Can generate an ID with a custom base (hex)
hex_id = Familia.generate_id(16)
[hex_id.class, hex_id.length == 64, hex_id.match?(/^[a-f0-9]+$/)]
#=> [String, true, true]

## Familia.generate_trace_id
Familia.respond_to?(:generate_trace_id)
#=> true

## Can generate a default base-36 trace ID
trace_id = Familia.generate_trace_id
[trace_id.class, trace_id.length > 5, trace_id.length < 20]
#=> [String, true, true]

## Can generate a trace ID with a custom base (hex)
hex_trace_id = Familia.generate_trace_id(16)
[hex_trace_id.class, hex_trace_id.length == 16]
#=> [String, true]

## Familia.generate_hex_id
Familia.respond_to?(:generate_hex_id)
#=> true

## Can generate a 256-bit hex ID
hex_id = Familia.generate_hex_id
[hex_id.class, hex_id.length == 64, hex_id.match?(/^[a-f0-9]+$/)]
#=> [String, true, true]

## Familia.generate_hex_trace_id
Familia.respond_to?(:generate_hex_trace_id)
#=> true

## Can generate a 64-bit hex trace ID
hex_trace_id = Familia.generate_hex_trace_id
[hex_trace_id.class, hex_trace_id.length == 16, hex_trace_id.match?(/^[a-f0-9]+$/)]
#=> [String, true, true]


##
## ID Shortening
##

## Familia.shorten_to_external_id
Familia.respond_to?(:shorten_to_external_id)
#=> true

## Can shorten hex ID to external ID (128 bits)
hex_id = Familia.generate_hex_id
external_id = Familia.shorten_to_external_id(hex_id)
[external_id.class, external_id.length < hex_id.length]
#=> [String, true]

## Can shorten hex ID to external ID with custom base (hex)
hex_id = Familia.generate_hex_id
hex_external_id = Familia.shorten_to_external_id(hex_id, base: 16)
[hex_external_id.class, hex_external_id.length == 32]
#=> [String, true]

## Familia.shorten_to_trace_id
Familia.respond_to?(:shorten_to_trace_id)
#=> true

## Can shorten hex ID to trace ID (64 bits)
hex_id = Familia.generate_hex_id
trace_id = Familia.shorten_to_trace_id(hex_id)
[trace_id.class, trace_id.length < hex_id.length]
#=> [String, true]

## Can shorten hex ID to trace ID with custom base (hex)
hex_id = Familia.generate_hex_id
hex_trace_id = Familia.shorten_to_trace_id(hex_id, base: 16)
[hex_trace_id.class, hex_trace_id.length == 16]
#=> [String, true]

## Shortened IDs are deterministic
hex_id = Familia.generate_hex_id
id1 = Familia.shorten_to_external_id(hex_id)
id2 = Familia.shorten_to_external_id(hex_id)
id1 == id2
#=> true

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

## Can create Redis key with default delimiter
key = Familia.rediskey('v1', 'customer', 'email')
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

## distinguisher handles basic types
str_result = Familia.distinguisher('test')
int_result = Familia.distinguisher(123)
sym_result = Familia.distinguisher(:symbol)
[str_result, int_result, sym_result]
#=> ["test", "123", "symbol"]

## distinguisher raises error for high-risk types with strict mode
begin
  Familia.distinguisher(true, strict_values: true)
rescue Familia::HighRiskFactor => e
  e.class
end
#=> Familia::HighRiskFactor

## distinguisher allows high-risk types with non-strict mode
result = Familia.distinguisher(false, strict_values: false)
result
#=> "false"

# Cleanup - restore defaults, leave nothing but footprints
Familia.delim(':')
Familia.suffix(:object)
Familia.default_expiration(0)
Familia.logical_database(nil)
Familia.prefix(nil)
