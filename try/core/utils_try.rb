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

## Can generate shorter ID with custom length
short_id = Familia.generate_id(length: 8)
[short_id.class, short_id.length > 5]
#=> [String, true]

## Can generate ID with custom encoding
hex_id = Familia.generate_id(encoding: 16)
[hex_id.class, hex_id.length > 30]
#=> [String, true]

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
redis_uri = Familia.redisuri(uri_str)
[redis_uri.class.name, redis_uri.host, redis_uri.port]
#=> ["URI::Redis", "localhost", 6379]

## Can handle nil URI (uses default)
default_uri = Familia.redisuri(nil)
default_uri.class.name
#=> "URI::Redis"

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

## generate_sha_hash creates consistent hash
hash1 = Familia.generate_sha_hash('user', '123', 'data')
hash2 = Familia.generate_sha_hash('user', '123', 'data')
[hash1.class, hash1 == hash2, hash1.length]
#=> [String, true, 64]

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

## generate_id raises error for invalid encoding
begin
  Familia.generate_id(encoding: 50)
rescue ArgumentError => e
  e.message.include?("between 2 and 36")
end
#=> true
