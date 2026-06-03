# try/features/encrypted_fields/key_material_try.rb
#
# frozen_string_literal: true

# Tests for the key_material: option on encrypted_field.
# key_material mixes additional entropy into key derivation (BLAKE2b),
# meaning wrong value produces garbage output (not auth_tag mismatch).
# Regression test for GitHub issue #280.

require 'base64'
require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Model with key_material from regular field
class KeyMaterialModel < Familia::Horreum
  feature :encrypted_fields

  identifier_field :id
  field :id
  field :user_salt

  encrypted_field :secret, key_material: ->(rec) { rec.user_salt }
end

# Model with key_material from transient field (returns RedactedString)
class KeyMaterialTransientModel < Familia::Horreum
  feature :encrypted_fields
  feature :transient_fields

  identifier_field :id
  field :id
  transient_field :passphrase

  encrypted_field :vault_key, key_material: ->(rec) { rec.passphrase }
end

# Model without key_material for backward compatibility test
class NoKeyMaterialModel < Familia::Horreum
  feature :encrypted_fields

  identifier_field :id
  field :id
  encrypted_field :token
end

Familia.dbclient.flushdb

## key_material present, correct value at decrypt succeeds
record = KeyMaterialModel.new(id: 'km-1', user_salt: 'salt-abc')
record.secret = 'my-secret'
decrypted = nil
record.secret.reveal { |pt| decrypted = pt }
decrypted
#=> "my-secret"

## key_material present, wrong value at decrypt fails with EncryptionError
record_wrong = KeyMaterialModel.new(id: 'km-2', user_salt: 'original-salt')
record_wrong.secret = 'bound-to-salt'
record_wrong.user_salt = 'changed-salt'
result = begin
  record_wrong.secret.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'Familia::EncryptionError'
end
result
#=> "Familia::EncryptionError"

## key_material present, value nil at encrypt derives different key
record_nil = KeyMaterialModel.new(id: 'km-3')
record_nil.secret = 'nil-salt-secret'
decrypted_nil = nil
record_nil.secret.reveal { |pt| decrypted_nil = pt }
decrypted_nil
#=> "nil-salt-secret"

## Different key_material values produce different ciphertexts
record_a = KeyMaterialModel.new(id: 'km-diff', user_salt: 'salt-A')
record_a.secret = 'same-plaintext'
ciphertext_a = record_a.instance_variable_get(:@secret).encrypted_value

record_b = KeyMaterialModel.new(id: 'km-diff', user_salt: 'salt-B')
record_b.secret = 'same-plaintext'
ciphertext_b = record_b.instance_variable_get(:@secret).encrypted_value

ciphertext_a != ciphertext_b
#=> true

## key_material proc returning RedactedString extracts .value correctly
record_transient = KeyMaterialTransientModel.new(id: 'km-transient-1')
record_transient.passphrase = 'my-passphrase'
record_transient.vault_key = 'vault-secret'
decrypted_transient = nil
record_transient.vault_key.reveal { |pt| decrypted_transient = pt }
decrypted_transient
#=> "vault-secret"

## RedactedString key_material: decrypt fails with changed passphrase
record_tamper = KeyMaterialTransientModel.new(id: 'km-tamper-1')
record_tamper.passphrase = 'original-passphrase'
record_tamper.vault_key = 'protected-key'
record_tamper.passphrase = 'tampered-passphrase'
result_tamper = begin
  record_tamper.vault_key.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'Familia::EncryptionError'
end
result_tamper
#=> "Familia::EncryptionError"

## No key_material option works as before (backward compat)
record_compat = NoKeyMaterialModel.new(id: 'compat-1')
record_compat.token = 'backward-compat-token'
decrypted_compat = nil
record_compat.token.reveal { |pt| decrypted_compat = pt }
decrypted_compat
#=> "backward-compat-token"

## Envelope contains key_material_fields metadata when key_material used
record_meta = KeyMaterialModel.new(id: 'km-meta-1', user_salt: 'meta-salt')
record_meta.secret = 'meta-secret'
encrypted_json = record_meta.instance_variable_get(:@secret).encrypted_value
envelope = Familia::JsonSerializer.parse(encrypted_json)
envelope['key_material_fields']
#=> ["key_material"]

## Envelope does NOT contain key_material_fields when not used
record_nometa = NoKeyMaterialModel.new(id: 'nometa-1')
record_nometa.token = 'no-material'
encrypted_json_nometa = record_nometa.instance_variable_get(:@token).encrypted_value
envelope_nometa = Familia::JsonSerializer.parse(encrypted_json_nometa)
envelope_nometa['key_material_fields']
#=> nil

## key_material with nil proc result encrypts without extra entropy
class NilKeyMaterialModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :data, key_material: ->(_rec) { nil }
end
@record_nil_proc = NilKeyMaterialModel.new(id: 'nil-km-1')
@record_nil_proc.data = 'nil-km-data'
@decrypted_nil_proc = nil
@record_nil_proc.data.reveal { |pt| @decrypted_nil_proc = pt }
@decrypted_nil_proc
#=> "nil-km-data"

## Nil key_material does not add key_material_fields to envelope
@encrypted_nil_km = @record_nil_proc.instance_variable_get(:@data).encrypted_value
@envelope_nil_km = Familia::JsonSerializer.parse(@encrypted_nil_km)
@envelope_nil_km['key_material_fields']
#=> nil

## key_material combined with aad_fields works together
class CombinedModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :tenant_id
  field :user_salt
  encrypted_field :api_secret, aad_fields: [:tenant_id], key_material: ->(r) { r.user_salt }
end
record_combined = CombinedModel.new(id: 'combined-1', tenant_id: 'tenant-abc', user_salt: 'salt-123')
record_combined.api_secret = 'combined-secret'
decrypted_combined = nil
record_combined.api_secret.reveal { |pt| decrypted_combined = pt }
decrypted_combined
#=> "combined-secret"

## Combined: changing aad_field fails decrypt
record_aad_fail = CombinedModel.new(id: 'aad-fail-1', tenant_id: 'tenant-orig', user_salt: 'salt-ok')
record_aad_fail.api_secret = 'aad-bound'
record_aad_fail.tenant_id = 'tenant-changed'
result_aad = begin
  record_aad_fail.api_secret.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'Familia::EncryptionError'
end
result_aad
#=> "Familia::EncryptionError"

## Combined: changing key_material also fails decrypt
record_km_fail = CombinedModel.new(id: 'km-fail-1', tenant_id: 'tenant-ok', user_salt: 'salt-orig')
record_km_fail.api_secret = 'km-bound'
record_km_fail.user_salt = 'salt-changed'
result_km = begin
  record_km_fail.api_secret.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'Familia::EncryptionError'
end
result_km
#=> "Familia::EncryptionError"

Familia.dbclient.flushdb
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
