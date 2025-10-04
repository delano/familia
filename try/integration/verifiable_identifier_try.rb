# try/core/verifiable_identifier_try.rb

require_relative '../support/helpers/test_helpers'
require 'familia/verifiable_identifier'

## Module is available
defined?(Familia::VerifiableIdentifier)
#=> "constant"

## Uses the development secret key by default when ENV is not set
Familia::VerifiableIdentifier::SECRET_KEY
#=> "cafef00dcafef00dcafef00dcafef00dcafef00dcafef00d"

# --- Verifiable ID Generation and Verification ---

## Generates a non-empty string ID
id = Familia::VerifiableIdentifier.generate_verifiable_id
id.is_a?(String) && !id.empty?
#=> true

## Generated ID is URL-safe (base36)
id = Familia::VerifiableIdentifier.generate_verifiable_id
id.match?(/[a-z0-9]+/ix)
#=> true

## Generates unique identifiers on subsequent calls
Familia::VerifiableIdentifier.generate_verifiable_id
#=/> Familia::VerifiableIdentifier.generate_verifiable_id

## A genuinely generated ID successfully verifies
id = Familia::VerifiableIdentifier.generate_verifiable_id
Familia::VerifiableIdentifier.verified_identifier?(id)
#=> true

## Fails verification for a completely random garbage string
Familia::VerifiableIdentifier.verified_identifier?('this-is-not-a-valid-id-at-all')
#=> false

## Fails verification for a string with invalid characters for the base
# A plus sign is not a valid base-36 character.
Familia::VerifiableIdentifier.verified_identifier?('this+is+invalid', 36)
#=> false

## Fails verification if the random part of the ID is tampered with
id = Familia::VerifiableIdentifier.generate_verifiable_id
tampered_id = id.dup
tampered_id[0] = (tampered_id[0] == 'a' ? 'b' : 'a') # Flip the first character
Familia::VerifiableIdentifier.verified_identifier?(tampered_id)
#=> false

## Fails verification if the tag part of the ID is tampered with
id = Familia::VerifiableIdentifier.generate_verifiable_id
tampered_id = id.dup
idx = tampered_id.length - 1
tampered_id[idx] = (tampered_id[idx] == 'a' ? 'b' : 'a') # Flip the last character
Familia::VerifiableIdentifier.verified_identifier?(tampered_id)
#=> false

## Works correctly with a different base (hexadecimal)
id_hex = Familia::VerifiableIdentifier.generate_verifiable_id(16)
Familia::VerifiableIdentifier.verified_identifier?(id_hex, 16)
#=> true

## Base 16 ID has the correct hex length (64 random + 16 tag = 80 chars)
id_hex = Familia::VerifiableIdentifier.generate_verifiable_id(16)
id_hex.length
#=> 80

# --- Plausibility Checks ---

## A genuinely generated ID is plausible
id = Familia::VerifiableIdentifier.generate_verifiable_id
Familia::VerifiableIdentifier.plausible_identifier?(id)
#=> true

## A well-formed but fake ID is still plausible
# A string of the correct length (62 for base 36) and charset is plausible
total_bits = (Familia::VerifiableIdentifier::RANDOM_HEX_LENGTH + Familia::VerifiableIdentifier::TAG_HEX_LENGTH) * 4
fake_id = 'a' * Familia::SecureIdentifier.min_length_for_bits(total_bits, 36)
Familia::VerifiableIdentifier.plausible_identifier?(fake_id)
#=> true

## Fails plausibility check if too short
short_id = 'a' * 60
Familia::VerifiableIdentifier.plausible_identifier?(short_id)
#=> false

## Fails plausibility check if too long
long_id = 'a' * 66
Familia::VerifiableIdentifier.plausible_identifier?(long_id)
#=> false

## Fails plausibility check for invalid characters
invalid_char_id = 'a' * 61 + '+'
Familia::VerifiableIdentifier.plausible_identifier?(invalid_char_id)
#=> false

## Fails plausibility check for nil input
Familia::VerifiableIdentifier.plausible_identifier?(nil)
#=> false

# --- Scoped Identifier Generation and Verification ---

## Scoped identifier generation produces different results than unscoped
scoped_id = Familia::VerifiableIdentifier.generate_verifiable_id(scope: "example.com")
unscoped_id = Familia::VerifiableIdentifier.generate_verifiable_id
scoped_id != unscoped_id
#=> true

## Scoped identifiers verify successfully with correct scope
scoped_id = Familia::VerifiableIdentifier.generate_verifiable_id(scope: "example.com")
Familia::VerifiableIdentifier.verified_identifier?(scoped_id, scope: "example.com")
#=> true

## Scoped identifiers fail verification with wrong scope
scoped_id = Familia::VerifiableIdentifier.generate_verifiable_id(scope: "example.com")
Familia::VerifiableIdentifier.verified_identifier?(scoped_id, scope: "different.com")
#=> false

## Scoped identifiers fail verification without scope parameter
scoped_id = Familia::VerifiableIdentifier.generate_verifiable_id(scope: "example.com")
Familia::VerifiableIdentifier.verified_identifier?(scoped_id)
#=> false

## Unscoped identifiers fail verification with scope parameter
unscoped_id = Familia::VerifiableIdentifier.generate_verifiable_id
Familia::VerifiableIdentifier.verified_identifier?(unscoped_id, scope: "example.com")
#=> false

## Empty string scope produces different identifier than nil scope
id_nil = Familia::VerifiableIdentifier.generate_verifiable_id(scope: nil)
id_empty = Familia::VerifiableIdentifier.generate_verifiable_id(scope: "")
id_nil != id_empty
#=> true

## Empty string scope verifies correctly
id_empty = Familia::VerifiableIdentifier.generate_verifiable_id(scope: "")
Familia::VerifiableIdentifier.verified_identifier?(id_empty, scope: "")
#=> true

## Short scope values work correctly
id_short = Familia::VerifiableIdentifier.generate_verifiable_id(scope: "a")
Familia::VerifiableIdentifier.verified_identifier?(id_short, scope: "a")
#=> true

## Long scope values work correctly
long_scope = "x" * 1000
id_long = Familia::VerifiableIdentifier.generate_verifiable_id(scope: long_scope)
Familia::VerifiableIdentifier.verified_identifier?(id_long, scope: long_scope)
#=> true

## Unicode scope values work correctly
unicode_scope = "测试🔒🔑"
id_unicode = Familia::VerifiableIdentifier.generate_verifiable_id(scope: unicode_scope)
Familia::VerifiableIdentifier.verified_identifier?(id_unicode, scope: unicode_scope)
#=> true

## Scoped identifiers work with different bases
id_hex = Familia::VerifiableIdentifier.generate_verifiable_id(scope: "test", base: 16)
Familia::VerifiableIdentifier.verified_identifier?(id_hex, scope: "test", base: 16)
#=> true

## Backward compatibility: existing method signatures still work
id = Familia::VerifiableIdentifier.generate_verifiable_id(36)
Familia::VerifiableIdentifier.verified_identifier?(id, 36)
#=> true

## Mixed parameter styles work correctly
id = Familia::VerifiableIdentifier.generate_verifiable_id(scope: "test", base: 16)
Familia::VerifiableIdentifier.verified_identifier?(id, scope: "test", base: 16)
#=> true
