# try/integration/verifiable_identifier_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# A dedicated HMAC secret is REQUIRED: the library intentionally has no
# committed fallback default (a known key would let anyone forge identifiers --
# see issue #310, S1). The secret is read lazily on first use, so requiring the
# module never raises; provide a test-only secret before the generate/verify
# cases below exercise it.
ENV['VERIFIABLE_ID_HMAC_SECRET'] ||= 'test-only-verifiable-id-hmac-secret-0123456789abcdef'

require 'familia/verifiable_identifier'

## Module is available
defined?(Familia::VerifiableIdentifier)
#=> "constant"

## Reads the HMAC secret lazily from the environment (no committed fallback)
Familia::VerifiableIdentifier.secret_key
#=> 'test-only-verifiable-id-hmac-secret-0123456789abcdef'

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

## reset_secret_key! clears memoization so the next read re-reads ENV (test API).
## Production never needs this; it lets a test swap the configured secret in-process.
@orig_hmac_secret = ENV['VERIFIABLE_ID_HMAC_SECRET']
Familia::VerifiableIdentifier.reset_secret_key!
ENV['VERIFIABLE_ID_HMAC_SECRET'] = 'rotated-secret-for-reset-test-0123456789abcdef'
@after_reset = Familia::VerifiableIdentifier.secret_key
# Restore the original secret and re-clear, so the original value is re-memoized
# and no rotated state leaks into a later case or a shared suite process.
ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_hmac_secret
Familia::VerifiableIdentifier.reset_secret_key!
@after_reset
#=> 'rotated-secret-for-reset-test-0123456789abcdef'

## An unset secret raises KeyError lazily (issue #310 S1). Uses a fresh key so a
## restore-on-failure is unnecessary: the case never mutates the configured value.
@orig_hmac_secret = ENV['VERIFIABLE_ID_HMAC_SECRET']
Familia::VerifiableIdentifier.reset_secret_key!
ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
begin
  Familia::VerifiableIdentifier.secret_key
  :did_not_raise
rescue KeyError
  :raised_key_error
ensure
  # Restore with delete-on-nil: ENV[key] = nil raises TypeError, which would mask
  # the KeyError assertion above and leave a stale memoized secret behind.
  if @orig_hmac_secret.nil?
    ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  else
    ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_hmac_secret
  end
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> :raised_key_error

## A present-but-empty secret raises KeyError too (issue #335): ENV.fetch treats
## "" as a hit, so without the blank guard it would HMAC under an empty key --
## silently reintroducing the forgeable-key weakness S1 closed.
@orig_hmac_secret = ENV['VERIFIABLE_ID_HMAC_SECRET']
Familia::VerifiableIdentifier.reset_secret_key!
ENV['VERIFIABLE_ID_HMAC_SECRET'] = ''
begin
  Familia::VerifiableIdentifier.secret_key
  :did_not_raise
rescue KeyError
  :raised_key_error
ensure
  # Restore with delete-on-nil: ENV[key] = nil raises TypeError, which would mask
  # the KeyError assertion above and leave a stale memoized secret behind.
  if @orig_hmac_secret.nil?
    ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  else
    ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_hmac_secret
  end
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> :raised_key_error

## A whitespace-only secret is blank too (issue #335): value.strip.empty? rejects
## "   " so a secret mangled by a YAML parser or templating tool can't slip
## through as an effectively-empty HMAC key.
@orig_hmac_secret = ENV['VERIFIABLE_ID_HMAC_SECRET']
Familia::VerifiableIdentifier.reset_secret_key!
ENV['VERIFIABLE_ID_HMAC_SECRET'] = '   '
begin
  Familia::VerifiableIdentifier.secret_key
  :did_not_raise
rescue KeyError
  :raised_key_error
ensure
  if @orig_hmac_secret.nil?
    ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  else
    ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_hmac_secret
  end
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> :raised_key_error

# --- IDENTIFIER_SECRET fallback (issue #423) ---
#
# Precedence: a nonblank VERIFIABLE_ID_HMAC_SECRET wins; otherwise a nonblank
# IDENTIFIER_SECRET; otherwise KeyError. Every case below saves BOTH variables,
# mutates them, and restores both in `ensure` (delete when the original was nil,
# since ENV[k] = nil raises TypeError), then re-clears memoization so no state
# leaks into a later case or a shared suite process.

## IDENTIFIER_SECRET alone (legacy unset) is read as the secret
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  ENV['IDENTIFIER_SECRET'] = 'preferred-identifier-secret-0123456789abcdef'
  Familia::VerifiableIdentifier.secret_key
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> 'preferred-identifier-secret-0123456789abcdef'

## IDENTIFIER_SECRET alone: generate/verify round-trips under the fallback secret
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  ENV['IDENTIFIER_SECRET'] = 'preferred-identifier-secret-0123456789abcdef'
  id = Familia::VerifiableIdentifier.generate_verifiable_id(scope: 'fallback')
  [
    Familia::VerifiableIdentifier.verified_identifier?(id, scope: 'fallback'),
    Familia::VerifiableIdentifier.verified_identifier?(id, scope: 'other'),
  ]
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> [true, false]

## Only the secret value matters, not which variable supplied it: an identifier
## minted under IDENTIFIER_SECRET verifies under the same value in the legacy var
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  ENV['IDENTIFIER_SECRET'] = 'shared-secret-across-variable-names-0123456789'
  id = Familia::VerifiableIdentifier.generate_verifiable_id
  Familia::VerifiableIdentifier.reset_secret_key!
  ENV.delete('IDENTIFIER_SECRET')
  ENV['VERIFIABLE_ID_HMAC_SECRET'] = 'shared-secret-across-variable-names-0123456789'
  Familia::VerifiableIdentifier.verified_identifier?(id)
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> true

## Both set nonblank: the legacy VERIFIABLE_ID_HMAC_SECRET wins
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV['VERIFIABLE_ID_HMAC_SECRET'] = 'legacy-wins-0123456789abcdef'
  ENV['IDENTIFIER_SECRET'] = 'preferred-loses-0123456789abcdef'
  Familia::VerifiableIdentifier.secret_key
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> 'legacy-wins-0123456789abcdef'

## Empty legacy ("") falls through to IDENTIFIER_SECRET instead of raising. This
## is the `${VERIFIABLE_ID_HMAC_SECRET:-}` container case.
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV['VERIFIABLE_ID_HMAC_SECRET'] = ''
  ENV['IDENTIFIER_SECRET'] = 'preferred-after-empty-legacy-0123456789abcdef'
  Familia::VerifiableIdentifier.secret_key
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> 'preferred-after-empty-legacy-0123456789abcdef'

## Whitespace-only legacy ("   ") is blank too and falls through to IDENTIFIER_SECRET
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV['VERIFIABLE_ID_HMAC_SECRET'] = '   '
  ENV['IDENTIFIER_SECRET'] = 'preferred-after-blank-legacy-0123456789abcdef'
  Familia::VerifiableIdentifier.secret_key
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> 'preferred-after-blank-legacy-0123456789abcdef'

## The value is returned as-is: surrounding whitespace on a nonblank secret is kept
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  ENV['IDENTIFIER_SECRET'] = '  padded-secret-0123456789abcdef  '
  Familia::VerifiableIdentifier.secret_key
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> '  padded-secret-0123456789abcdef  '

## Both unset raises KeyError
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  ENV.delete('IDENTIFIER_SECRET')
  Familia::VerifiableIdentifier.secret_key
  :did_not_raise
rescue KeyError
  :raised_key_error
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> :raised_key_error

## Both empty ("") raises KeyError
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV['VERIFIABLE_ID_HMAC_SECRET'] = ''
  ENV['IDENTIFIER_SECRET'] = ''
  Familia::VerifiableIdentifier.secret_key
  :did_not_raise
rescue KeyError
  :raised_key_error
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> :raised_key_error

## Legacy unset and IDENTIFIER_SECRET whitespace-only raises KeyError
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  ENV['IDENTIFIER_SECRET'] = '   '
  Familia::VerifiableIdentifier.secret_key
  :did_not_raise
rescue KeyError
  :raised_key_error
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> :raised_key_error

## The KeyError message names both variables so operators know what to set
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  ENV.delete('IDENTIFIER_SECRET')
  Familia::VerifiableIdentifier.secret_key
  :did_not_raise
rescue KeyError => e
  [e.message.include?('VERIFIABLE_ID_HMAC_SECRET'), e.message.include?('IDENTIFIER_SECRET')]
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> [true, true]

## The failure is not memoized: after a KeyError, fixing the environment makes
## the very next call succeed without reset_secret_key!
@orig_legacy = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', nil)
@orig_preferred = ENV.fetch('IDENTIFIER_SECRET', nil)
Familia::VerifiableIdentifier.reset_secret_key!
begin
  ENV.delete('VERIFIABLE_ID_HMAC_SECRET')
  ENV.delete('IDENTIFIER_SECRET')
  first = begin
    Familia::VerifiableIdentifier.secret_key
  rescue KeyError
    :raised_key_error
  end
  ENV['IDENTIFIER_SECRET'] = 'set-after-failure-0123456789abcdef'
  [first, Familia::VerifiableIdentifier.secret_key]
ensure
  @orig_legacy.nil? ? ENV.delete('VERIFIABLE_ID_HMAC_SECRET') : ENV['VERIFIABLE_ID_HMAC_SECRET'] = @orig_legacy
  @orig_preferred.nil? ? ENV.delete('IDENTIFIER_SECRET') : ENV['IDENTIFIER_SECRET'] = @orig_preferred
  Familia::VerifiableIdentifier.reset_secret_key!
end
#=> [:raised_key_error, 'set-after-failure-0123456789abcdef']
