# try/features/encrypted_fields/per_field_algorithm_try.rb
#
# frozen_string_literal: true
#
# Per-field algorithm pin (issue #334).
#
# `encrypted_field :name, algorithm: '...'` pins that field's WRITE algorithm to
# a specific registered provider via Familia::Encryption.encrypt_with, decoupling
# it from the registry's default-provider priority. The READ path is unchanged --
# the provider is always resolved from the stored envelope's own `algorithm`
# field -- so a pin can be added, changed, or removed without breaking ciphertext
# already at rest. That decoupling is the supported lever for a reader-before-
# writer format migration: install rbnacl fleet-wide so every node can READ
# XChaCha20, while keeping WRITES pinned to AES-256-GCM until every reader is
# confirmed capable, then drop the pin.
#
# AES-256-GCM (OpenSSL) is always available. The XChaCha assertions assume rbnacl
# is loaded -- the same environment assumption as algorithm_upgrade_try.rb, whose
# first check would already fail without it. No database writes: everything here
# exercises the in-memory field path.

require_relative '../../support/helpers/test_helpers'
require 'base64'

Familia.config.encryption_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.current_key_version = :v1
Familia::Encryption::Registry.setup!

class PerFieldAlgoModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :objid
  field :objid
  encrypted_field :default_field                                  # no pin -> default provider
  encrypted_field :aes_field, algorithm: 'aes-256-gcm'            # pinned AES-256-GCM
  encrypted_field :xchacha_field, algorithm: 'xchacha20poly1305'  # pinned XChaCha20
end

@record = PerFieldAlgoModel.new(objid: 'rec_1')
@record.default_field = 'default plaintext'
@record.aes_field = 'aes plaintext'
@record.xchacha_field = 'xchacha plaintext'

## Precondition: the registry default is XChaCha20-Poly1305 (rbnacl loaded)
Familia::Encryption::Registry.default_provider.algorithm
#=> 'xchacha20poly1305'

## An unpinned field writes with the default provider
Familia::JsonSerializer.parse(@record.default_field.encrypted_value)['algorithm']
#=> 'xchacha20poly1305'

## A field pinned to aes-256-gcm writes AES-256-GCM despite the XChaCha default
Familia::JsonSerializer.parse(@record.aes_field.encrypted_value)['algorithm']
#=> 'aes-256-gcm'

## A field pinned to xchacha20poly1305 writes XChaCha20-Poly1305
Familia::JsonSerializer.parse(@record.xchacha_field.encrypted_value)['algorithm']
#=> 'xchacha20poly1305'

## Per-field granularity: two fields on the SAME record select different algorithms
[
  Familia::JsonSerializer.parse(@record.aes_field.encrypted_value)['algorithm'],
  Familia::JsonSerializer.parse(@record.xchacha_field.encrypted_value)['algorithm'],
]
#=> ['aes-256-gcm', 'xchacha20poly1305']

## Reads are envelope-driven: the aes_field envelope decrypts even though the
## default provider is XChaCha, proving the read path uses the stored algorithm,
## not the field pin or the default. All three fields round-trip.
[
  @record.default_field.reveal { |p| p },
  @record.aes_field.reveal { |p| p },
  @record.xchacha_field.reveal { |p| p },
]
#=> ['default plaintext', 'aes plaintext', 'xchacha plaintext']

## The pin is introspectable via the field type's #algorithm reader; unpinned is nil
[
  PerFieldAlgoModel.field_types[:default_field].algorithm,
  PerFieldAlgoModel.field_types[:aes_field].algorithm,
  PerFieldAlgoModel.field_types[:xchacha_field].algorithm,
]
#=> [nil, 'aes-256-gcm', 'xchacha20poly1305']

## re_encrypt_fields! preserves each field's pinned algorithm (it does NOT drift to
## the default provider) -- the guarantee the reader-before-writer rollout relies on
@record.re_encrypt_fields!
[
  Familia::JsonSerializer.parse(@record.aes_field.encrypted_value)['algorithm'],
  Familia::JsonSerializer.parse(@record.xchacha_field.encrypted_value)['algorithm'],
  Familia::JsonSerializer.parse(@record.default_field.encrypted_value)['algorithm'],
]
#=> ['aes-256-gcm', 'xchacha20poly1305', 'xchacha20poly1305']

## ...and plaintext survives the re-encryption
[
  @record.aes_field.reveal { |p| p },
  @record.xchacha_field.reveal { |p| p },
]
#=> ['aes plaintext', 'xchacha plaintext']

## A pin composes with aad_fields
class PerFieldAlgoAadModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :objid
  field :objid
  field :owner
  encrypted_field :secret, algorithm: 'aes-256-gcm', aad_fields: [:owner]
end
@aad_rec = PerFieldAlgoAadModel.new(objid: 'rec_2', owner: 'alice')
@aad_rec.secret = 'bound secret'
Familia::JsonSerializer.parse(@aad_rec.secret.encrypted_value)['algorithm']
#=> 'aes-256-gcm'

## ...and still reveals with the AAD binding intact
@aad_rec.secret.reveal { |p| p }
#=> 'bound secret'

## An unregistered algorithm is NOT validated at field declaration...
class BadAlgoModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :objid
  field :objid
  encrypted_field :secret, algorithm: 'nonexistent-cipher'
end
BadAlgoModel.field_types[:secret].algorithm
#=> 'nonexistent-cipher'

## ...but raises Familia::EncryptionError naming the algorithm on the first write
@bad = BadAlgoModel.new(objid: 'rec_3')
begin
  @bad.secret = 'oops'
  'no-error'
rescue Familia::EncryptionError => e
  e.message.include?('nonexistent-cipher') ? 'raised-with-algorithm' : 'raised-generic'
end
#=> 'raised-with-algorithm'
