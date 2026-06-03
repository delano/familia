# try/features/encrypted_fields/aad_transient_proof_try.rb
#
# frozen_string_literal: true

# Proof: AAD with transient fields — can ciphertext encrypted with AAD
# be decrypted without providing the same fields?
#
# FINDINGS:
#
# 1. OTS secret.rb declares `encrypted_field :ciphertext` with NO aad_fields.
#    The transient fields (ciphertext_passphrase, ciphertext_domain) are
#    declared but not wired into encryption. Decryption works without them.
#
# 2. Familia's build_aad was updated to support unwrap_value on RedactedString,
#    which calls `.value` instead of `.to_s`.
#    This means transient fields (which wrap strings in RedactedString)
#    are now FULLY EFFECTIVE as AAD — different values produce different AAD.
#
# 3. Changing transient passphrase after encryption now correctly breaks
#    decryption, raising Familia::EncryptionError.
#
# 4. Using regular `field` as aad_fields also continues to work correctly.

require 'base64'

require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# --- Model A: Current OTS behavior (no AAD) ---

class SecretNoAAD < Familia::Horreum
  feature :encrypted_fields
  feature :transient_fields

  identifier_field :secretid
  field :secretid

  encrypted_field :ciphertext
  transient_field :ciphertext_passphrase
  transient_field :ciphertext_domain
end

# --- Model B: AAD with regular field (works correctly) ---

class SecretWithFieldAAD < Familia::Horreum
  feature :encrypted_fields

  identifier_field :secretid
  field :secretid
  field :owner_email

  encrypted_field :ciphertext, aad_fields: [:owner_email]
end

# --- Model C: AAD with two regular fields (order/swap test) ---

class SecretTwoFieldAAD < Familia::Horreum
  feature :encrypted_fields

  identifier_field :secretid
  field :secretid
  field :field_a
  field :field_b

  encrypted_field :ciphertext, aad_fields: [:field_a, :field_b]
end

# --- Model D: AAD with transient field (RedactedString.to_s problem) ---

class SecretWithTransientAAD < Familia::Horreum
  feature :encrypted_fields
  feature :transient_fields

  identifier_field :secretid
  field :secretid

  encrypted_field :ciphertext, aad_fields: [:ciphertext_passphrase]
  transient_field :ciphertext_passphrase
end

Familia.dbclient.flushdb

# ============================================================
# PART 1: Current OTS behavior — no AAD, decrypt without passphrase
# ============================================================

## No-AAD: decrypt succeeds without passphrase (current OTS behavior)
@s1 = SecretNoAAD.new(secretid: 'no-aad-1')
@s1.ciphertext_passphrase = 'user-supplied-passphrase'
@s1.ciphertext_domain = 'acme.example.com'
@s1.ciphertext = 'Attack at dawn'
@s1.save
@reloaded1 = SecretNoAAD.load('no-aad-1')
@d1 = nil
@reloaded1.ciphertext.reveal { |pt| @d1 = pt }
@d1
#=> "Attack at dawn"

## No-AAD: transient passphrase is nil after reload
@reloaded1.ciphertext_passphrase.nil?
#=> true

## No-AAD: transient domain is nil after reload
@reloaded1.ciphertext_domain.nil?
#=> true

# ============================================================
# PART 2: AAD with regular field — works as intended
# ============================================================

## Field-AAD: encrypt and decrypt with matching email succeeds
@s2 = SecretWithFieldAAD.new(secretid: 'field-aad-ok', owner_email: 'alice@example.com')
@s2.ciphertext = 'Bound to alice'
@d2 = nil
@s2.ciphertext.reveal { |pt| @d2 = pt }
@d2
#=> "Bound to alice"

## Field-AAD: changing email after encryption breaks decrypt
@s3 = SecretWithFieldAAD.new(secretid: 'field-aad-changed', owner_email: 'alice@example.com')
@s3.ciphertext = 'Originally for alice'
@s3.owner_email = 'mallory@evil.com'
@result_changed = begin
  @s3.ciphertext.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'EncryptionError'
end
@result_changed
#=> "EncryptionError"

## Field-AAD: save/reload with matching field succeeds
@s4 = SecretWithFieldAAD.new(secretid: 'field-aad-reload', owner_email: 'bob@example.com')
@s4.ciphertext = 'Survives reload'
@s4.save
@reloaded4 = SecretWithFieldAAD.load('field-aad-reload')
@d4 = nil
@reloaded4.ciphertext.reveal { |pt| @d4 = pt }
@d4
#=> "Survives reload"

# ============================================================
# PART 3: Transient AAD is fully effective (RedactedString unwrapping works)
# ============================================================

## Transient-AAD: RedactedString.to_s returns [REDACTED], not the value
@s5 = SecretWithTransientAAD.new(secretid: 'transient-aad-1')
@s5.ciphertext_passphrase = 'secret-phrase-123'
@s5.ciphertext_passphrase.to_s
#=> "[REDACTED]"

## Transient-AAD: different passphrases produce different AAD (RedactedString unwrapped)
@s6a = SecretWithTransientAAD.new(secretid: 'same-id')
@s6a.ciphertext_passphrase = 'passphrase-one'
@ft = SecretWithTransientAAD.field_types[:ciphertext]
@aad_a = @ft.send(:build_aad, @s6a)

@s6b = SecretWithTransientAAD.new(secretid: 'same-id')
@s6b.ciphertext_passphrase = 'completely-different-passphrase'
@aad_b = @ft.send(:build_aad, @s6b)
@aad_a == @aad_b
#=> false

## Transient-AAD: changing passphrase after encrypt breaks decrypt
@s7 = SecretWithTransientAAD.new(secretid: 'transient-aad-break')
@s7.ciphertext_passphrase = 'original-phrase'
@s7.ciphertext = 'Should be bound and is'
@s7.ciphertext_passphrase = 'totally-wrong-phrase'
@result_transient_changed = begin
  @s7.ciphertext.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'EncryptionError'
end
@result_transient_changed
#=> "EncryptionError"

## Transient-AAD: nil passphrase also produces same AAD (nil.to_s == "")
# Wait — nil transient returns nil from getter, and nil.to_s == ""
# while RedactedString.to_s == "[REDACTED]". So nil vs set DOES differ.
@s8a = SecretWithTransientAAD.new(secretid: 'nil-vs-set')
@aad_nil = @ft.send(:build_aad, @s8a)

@s8b = SecretWithTransientAAD.new(secretid: 'nil-vs-set')
@s8b.ciphertext_passphrase = 'any-value'
@aad_set = @ft.send(:build_aad, @s8b)
@aad_nil == @aad_set
#=> false

## Transient-AAD: nil vs set does matter — encrypt with passphrase, clear to nil, decrypt fails
@s9 = SecretWithTransientAAD.new(secretid: 'nil-breaks')
@s9.ciphertext_passphrase = 'was-set'
@s9.ciphertext = 'Encrypted with passphrase set'
# Simulate what happens after reload (transient is nil)
@s9.instance_variable_set(:@ciphertext_passphrase, nil)
@result_nil_clear = begin
  @s9.ciphertext.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'EncryptionError'
end
@result_nil_clear
#=> "EncryptionError"

# ============================================================
# PART 4: Contrast — what regular field AAD looks like
# ============================================================

## Field-AAD: swapping two AAD values breaks decrypt (order matters)
@s_swap = SecretTwoFieldAAD.new(secretid: 'swap-test', field_a: 'alpha', field_b: 'beta')
@s_swap.ciphertext = 'order-bound content'
@s_swap.field_a = 'beta'
@s_swap.field_b = 'alpha'
@result_swap = begin
  @s_swap.ciphertext.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'EncryptionError'
end
@result_swap
#=> "EncryptionError"

## Field-AAD: missing one of two fields breaks decrypt
@s_miss = SecretTwoFieldAAD.new(secretid: 'miss-test', field_a: 'alpha', field_b: 'beta')
@s_miss.ciphertext = 'needs both'
@s_miss.field_b = nil
@result_miss = begin
  @s_miss.ciphertext.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'EncryptionError'
end
@result_miss
#=> "EncryptionError"

## Field-AAD: different emails produce different AAD (correct behavior)
@ft2 = SecretWithFieldAAD.field_types[:ciphertext]
@fa = SecretWithFieldAAD.new(secretid: 'cmp-id', owner_email: 'alice@example.com')
@fb = SecretWithFieldAAD.new(secretid: 'cmp-id', owner_email: 'bob@example.com')
@aad_alice = @ft2.send(:build_aad, @fa)
@aad_bob = @ft2.send(:build_aad, @fb)
@aad_alice == @aad_bob
#=> false

# Cleanup
Familia.dbclient.flushdb
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
