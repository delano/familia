# try/core/utils_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test Familia utility methods and helpers

## Familia has generate_id method
Familia.respond_to?(:generate_id)
#=> true

## Can generate default ID
id = Familia.generate_id
[id.class, id.length > 10]
#=> [String, true]

## Generated IDs are unique each time
id1 = Familia.generate_id
id2 = Familia.generate_id
id1 != id2
#=> true

## Can generate ID with custom base encoding
hex_id = Familia.generate_id(16)
[hex_id.class, hex_id.length > 30]
#=> [String, true]

## Has generate_trace_id method
Familia.respond_to?(:generate_trace_id)
#=> true

## Can generate trace ID with default base-36
trace_id = Familia.generate_trace_id
[trace_id.class, trace_id.length > 5, trace_id.length < 20]
#=> [String, true, true]

## Can generate trace ID with custom base
hex_trace_id = Familia.generate_trace_id(16)
[hex_trace_id.class, hex_trace_id.length == 16]
#=> [String, true]

## Has shorten_to_external_id method
Familia.respond_to?(:shorten_to_external_id)
#=> true

## Can shorten to external ID (128 bits)
full_id = Familia.generate_id
external_id = Familia.shorten_to_external_id(full_id)
[external_id.class, external_id.length < full_id.length]
#=> [String, true]

## Can shorten to external ID with custom base
full_id = Familia.generate_id
hex_external_id = Familia.shorten_to_external_id(full_id, base: 16)
[hex_external_id.class, hex_external_id.length == 32]
#=> [String, true]

## Has shorten_to_trace_id method
Familia.respond_to?(:shorten_to_trace_id)
#=> true

## Can shorten to trace ID (64 bits)
full_id = Familia.generate_id
trace_id = Familia.shorten_to_trace_id(full_id)
[trace_id.class, trace_id.length < full_id.length]
#=> [String, true]

## Can shorten to trace ID with custom base
full_id = Familia.generate_id
hex_trace_id = Familia.shorten_to_trace_id(full_id, base: 16)
[hex_trace_id.class, hex_trace_id.length == 16]
#=> [String, true]

## Shortened IDs are deterministic
full_id = Familia.generate_id
external_id1 = Familia.shorten_to_external_id(full_id)
external_id2 = Familia.shorten_to_external_id(full_id)
external_id1 == external_id2
#=> true

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

## Can split values with delimiter
parts = Familia.split('a|b|c')
parts
#=> ["a", "b", "c"]

# Reset delimiter (delim was changed to '|' so delimiter is still '|')
# Current delimiter is still '|' from the test above

## Can split with current delimiter
parts = Familia.split('a|b|c')
parts
#=> ["a", "b", "c"]

## Can create Redis key with current delimiter
key = Familia.rediskey('v1', 'customer', 'email')
key
#=> "v1|customer|email"

# Reset to default delimiter for remaining tests
Familia.delim(':')

## Can split with default delimiter after reset
parts = Familia.split('user:123:data')
parts
#=> ["user:123:data"]

## Can create Redis key with default delimiter
key = Familia.rediskey('v1', 'customer', 'email')
key
#=> "v1|customer|email"

## redisuri converts string to Redis URI
uri_str = 'redis://localhost:6379/1'
redis_uri = URI.parse(uri_str)
[redis_uri.host, redis_uri.port]
#=> ["localhost", 6379]

## Can handle nil URI (uses default)
URI.parse('redis://localhost:6379/1')
#=:> URI::Redis

## Can handle nil URI (uses default)
URI.parse(nil)
#=!> URI::InvalidURIError

## qstamp returns integer timestamp by default
stamp = Familia.qstamp
stamp.class
#=> Integer

## qstamp with pattern returns formatted string
formatted = Familia.qstamp(3600, pattern: '%Y%m%d%H')
formatted.class
#=> String

## qstamp works with custom time
test_time = Time.new(2023, 6, 15, 14, 30, 0)
custom_stamp = Familia.qstamp(3600, time: test_time)
custom_stamp.class
#=> Integer

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
result = Familia.distinguisher(true, strict_values: false)
result
#=> "true"

# Cleanup - restore defaults, leave nothing but footprints
Familia.delim(':')
Familia.suffix(:object)
Familia.ttl(0)
Familia.db(nil)
Familia.prefix(nil)
