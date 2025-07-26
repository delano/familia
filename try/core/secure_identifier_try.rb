# try/core/secure_identifier_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test Familia::SecureIdentifier methods

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

# Cleanup - restore defaults, leave nothing but footprints
Familia.delim(':')
Familia.suffix(:object)
Familia.default_expiration(0)
Familia.logical_database(nil)
Familia.prefix(nil)
