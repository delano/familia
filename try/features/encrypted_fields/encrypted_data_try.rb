# try/features/encrypted_fields/encrypted_data_try.rb
#
# frozen_string_literal: true

# Tests for EncryptedData value object methods added in issue #280:
# with_metadata, to_json, has_key_material?, stored_aad_fields,
# and round-trip through from_json.

require 'base64'
require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

@base = Familia::Encryption::EncryptedData.new(
  algorithm: 'xchacha20-poly1305',
  nonce: Base64.strict_encode64('n' * 24),
  ciphertext: Base64.strict_encode64('cipher'),
  auth_tag: Base64.strict_encode64('t' * 16),
  key_version: 'v1',
  encoding: 'UTF-8'
)

## with_metadata returns new instance with envelope_version set
@v2 = @base.with_metadata(envelope_version: 2)
@v2.envelope_version
#=> 2

## with_metadata preserves original crypto fields
@v2.algorithm
#=> "xchacha20-poly1305"

## with_metadata original is unchanged (Data is immutable)
@base.envelope_version
#=> nil

## with_metadata sets aad_fields
@with_aad = @base.with_metadata(envelope_version: 2, aad_fields: ['org_id', 'region'])
@with_aad.aad_fields
#=> ["org_id", "region"]

## with_metadata sets key_material_fields
@with_km = @base.with_metadata(envelope_version: 2, key_material_fields: ['key_material'])
@with_km.key_material_fields
#=> ["key_material"]

## to_h omits nil metadata keys via compact
@base.to_h.key?(:envelope_version)
#=> false

## to_h includes non-nil metadata keys
@v2.to_h[:envelope_version]
#=> 2

## to_json produces valid JSON string
@json = @v2.to_json
@json.is_a?(String)
#=> true

## to_json round-trips through from_json
@roundtrip = Familia::Encryption::EncryptedData.from_json(@json)
@roundtrip.envelope_version
#=> 2

## Round-trip preserves algorithm
@roundtrip.algorithm
#=> "xchacha20-poly1305"

## Round-trip preserves encoding
@roundtrip.encoding
#=> "UTF-8"

## Full metadata round-trip through JSON
@full = @base.with_metadata(
  envelope_version: 2,
  aad_fields: ['tenant_id'],
  key_material_fields: ['key_material']
)
@full_rt = Familia::Encryption::EncryptedData.from_json(@full.to_json)
@full_rt.aad_fields
#=> ["tenant_id"]

## Full metadata round-trip preserves key_material_fields
@full_rt.key_material_fields
#=> ["key_material"]

## has_key_material? returns false when nil
@base.has_key_material?
#=> false

## has_key_material? returns false when empty array
@empty_km = @base.with_metadata(key_material_fields: [])
@empty_km.has_key_material?
#=> false

## has_key_material? returns true when populated
@with_km.has_key_material?
#=> true

## stored_aad_fields returns nil when aad_fields is nil
@base.stored_aad_fields
#=> nil

## stored_aad_fields returns symbolized field names
@with_aad.stored_aad_fields
#=> [:org_id, :region]

## stored_aad_fields round-trips through JSON (string keys become symbols)
@aad_rt = Familia::Encryption::EncryptedData.from_json(@with_aad.to_json)
@aad_rt.stored_aad_fields
#=> [:org_id, :region]

## from_json with Hash input handles new metadata fields
@hash_input = {
  'algorithm' => 'xchacha20-poly1305',
  'nonce' => Base64.strict_encode64('n' * 24),
  'ciphertext' => Base64.strict_encode64('data'),
  'auth_tag' => Base64.strict_encode64('t' * 16),
  'key_version' => 'v1',
  'envelope_version' => 2,
  'aad_fields' => ['owner_id'],
}
@from_hash = Familia::Encryption::EncryptedData.from_json(@hash_input)
@from_hash.envelope_version
#=> 2

## from_json with Hash input preserves aad_fields
@from_hash.aad_fields
#=> ["owner_id"]

## from_json with old-format Hash (no metadata) defaults to nil
@old_hash = {
  'algorithm' => 'xchacha20-poly1305',
  'nonce' => Base64.strict_encode64('n' * 24),
  'ciphertext' => Base64.strict_encode64('data'),
  'auth_tag' => Base64.strict_encode64('t' * 16),
  'key_version' => 'v1',
}
@from_old = Familia::Encryption::EncryptedData.from_json(@old_hash)
@from_old.envelope_version
#=> nil

## Old-format envelope has_key_material? is false
@from_old.has_key_material?
#=> false

Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
