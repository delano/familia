# try/features/encryption/algorithm_upgrade_try.rb
#
# frozen_string_literal: true

# Locks in the algorithm-upgrade contract: installing rbnacl flips the DEFAULT
# write algorithm to XChaCha20-Poly1305 (provider priority), while every
# existing AES-256-GCM envelope keeps decrypting because the read path selects
# the provider (and that provider's KDF) from the envelope's own `algorithm`
# field -- never from the default provider. This is the exact upgrade path an
# application takes when it adds libsodium to a deployment whose data at rest
# is entirely AES-256-GCM (see examples/encryption_upgrade_proof for the
# multi-process version that also runs against the released 2.10.1 gem).
#
# Also pins the cross-provider confusion property: relabeling an envelope's
# algorithm between the two REGISTERED providers is rejected (nonce-size
# validation), not just relabeling to an unknown algorithm.
#
# No database writes: everything here exercises the in-memory field path.

require_relative '../../support/helpers/test_helpers'
require 'base64'

set_test_encryption_keys({ v1: Base64.strict_encode64('a' * 32),
                           v2: Base64.strict_encode64('b' * 32) },
                         current_version: :v2)

class AlgorithmUpgradeSecret < Familia::Horreum
  feature :encrypted_fields
  identifier_field :objid
  field :objid
  encrypted_field :ciphertext
end

@aes_mgr = Familia::Encryption::Manager.new(algorithm: 'aes-256-gcm')
# Build the context exactly as EncryptedFieldType#build_context does, from the
# class's runtime name (tryouts may namespace classes defined in a try file).
@ctx = "#{AlgorithmUpgradeSecret.name}:ciphertext:sec_1"
# With no aad_fields, EncryptedFieldType#build_aad is the same plain-joined
# string as the context -- craft envelopes exactly as the field path would.
@aes_envelope = @aes_mgr.encrypt('pre-upgrade secret', context: @ctx, additional_data: @ctx)

## With rbnacl loaded, the registry's default is XChaCha20-Poly1305 by priority
Familia::Encryption::Registry.setup!
Familia::Encryption::Registry.default_provider.algorithm
#=> 'xchacha20poly1305'

## ...and it wins because its priority outranks AES-GCM's
[Familia::Encryption::Providers::XChaCha20Poly1305Provider.priority,
 Familia::Encryption::Providers::AESGCMProvider.priority]
#=> [100, 50]

## Field-level POSITIVE cross-algorithm read: an AES envelope injected into a
## record the way DB hydration does -- wrapped in the StoredEnvelope provenance
## marker (#405); a bare envelope string would be encrypted as plaintext --
## reveals fine while the default is XChaCha
@record = AlgorithmUpgradeSecret.new(objid: 'sec_1')
@record.ciphertext = Familia::Encryption::StoredEnvelope.new(payload: @aes_envelope)
@record.ciphertext.reveal { |plaintext| plaintext }
#=> 'pre-upgrade secret'

## The injected envelope is passed through byte-identically (no re-encryption)
@record.ciphertext.encrypted_value.equal?(@aes_envelope) ||
  @record.ciphertext.encrypted_value == @aes_envelope
#=> true

## New assignments through the same field now encrypt with XChaCha20-Poly1305
@fresh = AlgorithmUpgradeSecret.new(objid: 'sec_2')
@fresh.ciphertext = 'post-upgrade secret'
Familia::JsonSerializer.parse(@fresh.ciphertext.encrypted_value)['algorithm']
#=> 'xchacha20poly1305'

## re_encrypt_fields! upgrades an AES envelope to the current algorithm in place
@migrate = AlgorithmUpgradeSecret.new(objid: 'sec_1')
@migrate.ciphertext = Familia::Encryption::StoredEnvelope.new(payload: @aes_envelope)
@migrate.re_encrypt_fields!
Familia::JsonSerializer.parse(@migrate.ciphertext.encrypted_value)['algorithm']
#=> 'xchacha20poly1305'

## ...preserving the plaintext across the algorithm upgrade
@migrate.ciphertext.reveal { |plaintext| plaintext }
#=> 'pre-upgrade secret'

## Cross-version AND cross-algorithm at once: an AES envelope under the retired
## v1 master key still decrypts while current config is v2 + XChaCha default
Familia.config.current_key_version = :v1
@aes_v1 = @aes_mgr.encrypt('oldest data', context: @ctx, additional_data: @ctx)
Familia.config.current_key_version = :v2
Familia::Encryption.decrypt(@aes_v1, context: @ctx, additional_data: @ctx)
#=> 'oldest data'

## Relabeling an AES envelope as xchacha20poly1305 (both providers registered)
## is rejected: the 12-byte GCM nonce fails the XChaCha 24-byte size check
@relabeled = Familia::JsonSerializer.parse(@aes_envelope).merge('algorithm' => 'xchacha20poly1305')
begin
  Familia::Encryption.decrypt(Familia::JsonSerializer.dump(@relabeled),
                              context: @ctx, additional_data: @ctx)
  'decrypted-unexpectedly'
rescue Familia::EncryptionError
  'failed-as-expected'
end
#=> 'failed-as-expected'

## ...and the reverse relabeling (XChaCha envelope marked aes-256-gcm) fails too
@xchacha_envelope = Familia::Encryption.encrypt('fresh', context: @ctx, additional_data: @ctx)
@relabeled_back = Familia::JsonSerializer.parse(@xchacha_envelope).merge('algorithm' => 'aes-256-gcm')
begin
  Familia::Encryption.decrypt(Familia::JsonSerializer.dump(@relabeled_back),
                              context: @ctx, additional_data: @ctx)
  'decrypted-unexpectedly'
rescue Familia::EncryptionError
  'failed-as-expected'
end
#=> 'failed-as-expected'

# Restore config for any subsequent try files sharing the process. One test
# above rewinds current_key_version to :v1 mid-file; this puts the whole
# override back, keys included (issue #363).
clear_test_encryption_keys
