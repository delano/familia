# try/features/encrypted_fields/re_encrypt_fields_try.rb
#
# frozen_string_literal: true
#
# Coverage for issue #235: `re_encrypt_fields!` silently no-ops.
#
# These tests are designed to fail BEFORE the fix and pass AFTER.
#
# The bug: when `re_encrypt_fields!` iterates encrypted fields it calls the
# setter with the existing ConcealedString. The setter detects
# `value.is_a?(ConcealedString)` and stores it as-is without re-encrypting,
# so the stored ciphertext (and its `key_version`) is unchanged even when
# the current key version has been rotated.
#
# A plaintext round-trip is NOT sufficient to detect this: as long as the
# original key remains in the keyring during rotation, the original
# ciphertext still decrypts cleanly. The only way to observe the bug is to
# inspect the RAW stored JSON and verify `key_version` has moved to the
# current version.

require 'base64'
require 'json'

require_relative '../../support/helpers/test_helpers'

# Capture original encryption state so teardown can restore it.
@original_encryption_keys = Familia.config.encryption_keys
@original_current_key_version = Familia.config.current_key_version

# Two distinct versioned keys; v1 is current at setup time.
@test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32),
}

Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v1

# Model with two encrypted fields and one plain field.
class ReEncryptTarget < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :label
  encrypted_field :secret
  encrypted_field :token
end

# Track identifiers so teardown can purge records.
@created_ids = []

## re_encrypt_fields! rotates ciphertext to current key version
# Save a record under v1, rotate current to v2, then re_encrypt_fields! + save.
# Inspect raw stored JSON and assert key_version is now "v2". This is the
# canary test for the bug in #235.
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v1

@obj = ReEncryptTarget.new(id: 're-enc-1', label: 'one')
@obj.secret = 'secret-value-one'
@obj.token  = 'token-value-one'
@obj.save
@created_ids << @obj.id

# Rotate: keep v1 available for decrypt, make v2 the current encrypt target.
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v2

# Reload fresh from the database so the in-memory ConcealedString comes
# from stored ciphertext, not from the original assignment.
@fresh = ReEncryptTarget.load('re-enc-1')
@fresh.re_encrypt_fields!
@fresh.save

raw_secret = Familia.dbclient.hget(@fresh.dbkey, 'secret')
parsed = JSON.parse(raw_secret)
parsed['key_version']
#=> 'v2'

## plaintext round-trips unchanged after rotation
# Values must decrypt to their original plaintext under the new key version.
@reloaded = ReEncryptTarget.load('re-enc-1')
[
  @reloaded.secret.reveal { |v| v },
  @reloaded.token.reveal { |v| v },
]
#=> ['secret-value-one', 'token-value-one']

## all encrypted fields on a multi-field model are rotated
# Both `secret` and `token` must have key_version == v2 in storage.
raw_secret = Familia.dbclient.hget(@fresh.dbkey, 'secret')
raw_token  = Familia.dbclient.hget(@fresh.dbkey, 'token')
[
  JSON.parse(raw_secret)['key_version'],
  JSON.parse(raw_token)['key_version'],
]
#=> ['v2', 'v2']

## nil-valued encrypted fields are skipped, not errored
# Record with one encrypted field nil and one populated. re_encrypt_fields!
# must return true without raising and must not introduce ciphertext for the
# nil field.
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v1

@partial = ReEncryptTarget.new(id: 're-enc-partial', label: 'partial')
@partial.secret = 'only-secret-set'
# @partial.token intentionally left nil
@partial.save
@created_ids << @partial.id

Familia.config.current_key_version = :v2
@partial_fresh = ReEncryptTarget.load('re-enc-partial')
result = @partial_fresh.re_encrypt_fields!
@partial_fresh.save

raw_token = Familia.dbclient.hget(@partial_fresh.dbkey, 'token')
raw_secret = Familia.dbclient.hget(@partial_fresh.dbkey, 'secret')
# Nil encrypted fields are stored as the JSON literal "null" by Familia's
# scalar serializer -- not as an encrypted envelope. The contract we care
# about here is: re_encrypt_fields! must not turn a nil field into
# ciphertext. Parsing "null" yields nil, so we assert that directly.
token_parsed = JSON.parse(raw_token) rescue :unparseable
[result, token_parsed, JSON.parse(raw_secret)['key_version']]
#=> [true, nil, 'v2']

## is idempotent when current key is unchanged
# Calling re_encrypt_fields! twice without rotating must succeed both times
# and plaintext must still round-trip. Ciphertext bytes may differ each call
# (fresh nonces) but the key_version remains the current version.
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v2

@idem = ReEncryptTarget.new(id: 're-enc-idem', label: 'idem')
@idem.secret = 'idem-secret'
@idem.token  = 'idem-token'
@idem.save
@created_ids << @idem.id

r1 = @idem.re_encrypt_fields!
@idem.save
r2 = @idem.re_encrypt_fields!
@idem.save

@idem_fresh = ReEncryptTarget.load('re-enc-idem')
raw_secret = Familia.dbclient.hget(@idem_fresh.dbkey, 'secret')
[
  r1,
  r2,
  JSON.parse(raw_secret)['key_version'],
  @idem_fresh.secret.reveal { |v| v },
  @idem_fresh.token.reveal  { |v| v },
]
#=> [true, true, 'v2', 'idem-secret', 'idem-token']

## caller must save to persist re-encrypted values
# re_encrypt_fields! mutates in-memory state only. Until `save` is called,
# the stored ciphertext still carries the previous key_version. This
# documents the contract that the caller drives persistence.
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v1

@contract = ReEncryptTarget.new(id: 're-enc-contract', label: 'contract')
@contract.secret = 'contract-secret'
@contract.token  = 'contract-token'
@contract.save
@created_ids << @contract.id

Familia.config.current_key_version = :v2
@contract_fresh = ReEncryptTarget.load('re-enc-contract')
@contract_fresh.re_encrypt_fields!
# NOTE: deliberately NOT calling save.

raw_secret_before_save = Familia.dbclient.hget(@contract_fresh.dbkey, 'secret')
JSON.parse(raw_secret_before_save)['key_version']
#=> 'v1'

# Teardown: delete test records and restore original encryption config.
@created_ids.uniq.each do |id|
  begin
    ReEncryptTarget.destroy!(id)
  rescue StandardError
    # best effort cleanup
  end
end

Familia.config.encryption_keys = @original_encryption_keys
Familia.config.current_key_version = @original_current_key_version
