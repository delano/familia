# try/core/secure_identifier_try.rb

# Test Familia::SecureIdentifier methods

require_relative '../support/helpers/test_helpers'

Familia.debug = false

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

## Familia.generate_lite_id
Familia.respond_to?(:generate_lite_id)
#=> true

## Can generate a default base-36 lite ID
lite_id = Familia.generate_lite_id
[lite_id.class, lite_id.length > 10, lite_id.match?(/^[a-z0-9]+$/)]
#=> [String, true, true]

## Can generate a lite ID with a custom base (hex)
hex_lite_id = Familia.generate_lite_id(16)
[hex_lite_id.class, hex_lite_id.length == 32, hex_lite_id.match?(/^[a-f0-9]+$/)]
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
[hex_trace_id.class, hex_trace_id.length == 16, hex_trace_id.match?(/^[a-f0-9]+$/)]
#=> [String, true, true]

## Generated lite IDs are unique
[Familia.generate_lite_id == Familia.generate_lite_id]
#=> [false]

## Generated trace IDs are unique
[Familia.generate_trace_id == Familia.generate_trace_id]
#=> [false]

## Familia.shorten_to_trace_id
Familia.respond_to?(:shorten_to_trace_id)
#=> true

## Can shorten hex ID to trace ID (64 bits)
hex_id = Familia.generate_id(16)
trace_id = Familia.shorten_to_trace_id(hex_id)
[trace_id.class, trace_id.length < hex_id.length]
#=> [String, true]

## Can shorten hex ID to trace ID with custom base (hex)
hex_id = Familia.generate_id(16)
hex_trace_id = Familia.shorten_to_trace_id(hex_id, base: 16)
[hex_trace_id.class, hex_trace_id.length == 16]
#=> [String, true]

## Familia.truncate_hex
Familia.respond_to?(:truncate_hex)
#=> true

## Can truncate hex ID to 128 bits by default
hex_id = Familia.generate_id(16)
truncated_id = Familia.truncate_hex(hex_id)
[truncated_id.class, truncated_id.length < hex_id.length]
#=> [String, true]

## Can truncate hex ID to a custom bit length (64 bits)
hex_id = Familia.generate_id(16)
truncated_64 = Familia.truncate_hex(hex_id, bits: 64)
[truncated_64.class, truncated_64.length < hex_id.length]
#=> [String, true]

## Can truncate with a custom base (hex)
hex_id = Familia.generate_id(16)
hex_truncated = Familia.truncate_hex(hex_id, bits: 128, base: 16)
[hex_truncated.class, hex_truncated.length == 32]
#=> [String, true]

## Truncated IDs are deterministic
hex_id = Familia.generate_id(16)
id1 = Familia.truncate_hex(hex_id)
id2 = Familia.truncate_hex(hex_id)
id1 == id2
#=> true

## Raises error for invalid hex
begin
  Familia.truncate_hex("not-a-hex-string")
rescue ArgumentError => e
  e.message
end
#=> "Invalid hexadecimal string: not-a-hex-string"

## Raises error if input bits are less than output bits
begin
  Familia.truncate_hex("abc", bits: 64)
rescue ArgumentError => e
  e.message
end
#=> "Input bits (12) cannot be less than desired output bits (64)."

## Shortened IDs are deterministic
hex_id = Familia.generate_id(16)
id1 = Familia.shorten_to_trace_id(hex_id)
id2 = Familia.shorten_to_trace_id(hex_id)
id1 == id2
#=> true

# Cleanup - restore defaults, leave nothing but footprints
Familia.delim(':')
Familia.suffix(:object)
Familia.default_expiration(0)
Familia.logical_database(nil)
Familia.prefix(nil)
