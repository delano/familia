# try/features/encrypted_fields/aad_transient_fix_try.rb
#
# frozen_string_literal: true

# Tests for RedactedString.value extraction fix in build_aad.
# Verifies that transient fields in aad_fields are handled correctly
# by extracting the underlying value from RedactedString wrappers.
# Regression test for GitHub issue #280.

require 'base64'
require 'digest'
require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Model with transient field in aad_fields
class TransientAADModel < Familia::Horreum
  feature :encrypted_fields
  feature :transient_fields

  identifier_field :id
  field :id
  transient_field :passphrase
  encrypted_field :secret, aad_fields: [:passphrase]
end

# Model with mixed regular and transient fields in aad_fields
class MixedAADModel < Familia::Horreum
  feature :encrypted_fields
  feature :transient_fields

  identifier_field :id
  field :id
  field :region
  transient_field :session_token
  encrypted_field :api_key, aad_fields: [:region, :session_token]
end

Familia.dbclient.flushdb

@field_type = TransientAADModel.field_types[:secret]
@mixed_ft = MixedAADModel.field_types[:api_key]

## Transient field in aad_fields produces different AAD for different values
@record1 = TransientAADModel.new(id: 'aad-transient-1')
@record1.passphrase = 'secret-pass-A'
@record2 = TransientAADModel.new(id: 'aad-transient-1')
@record2.passphrase = 'secret-pass-B'
@aad1 = @field_type.send(:build_aad, @record1)
@aad2 = @field_type.send(:build_aad, @record2)
@aad1 != @aad2
#=> true

## Transient field in aad_fields produces same AAD for same value
@record3 = TransientAADModel.new(id: 'aad-transient-2')
@record3.passphrase = 'identical-pass'
@record4 = TransientAADModel.new(id: 'aad-transient-2')
@record4.passphrase = 'identical-pass'
@aad3 = @field_type.send(:build_aad, @record3)
@aad4 = @field_type.send(:build_aad, @record4)
@aad3 == @aad4
#=> true

## Transient field value is nil - AAD still computed with empty string
@record_nil = TransientAADModel.new(id: 'aad-transient-nil')
@aad_nil = @field_type.send(:build_aad, @record_nil)
@aad_nil.is_a?(String) && !@aad_nil.empty?
#=> true

## Nil transient field produces same AAD as explicitly nil
@record_explicit_nil = TransientAADModel.new(id: 'aad-transient-nil')
@record_explicit_nil.passphrase = nil
@aad_explicit_nil = @field_type.send(:build_aad, @record_explicit_nil)
@aad_nil == @aad_explicit_nil
#=> true

## Mixed regular fields + transient fields extracts all values correctly
@mixed = MixedAADModel.new(id: 'mixed-1', region: 'us-east')
@mixed.session_token = 'sess-abc123'
@mixed_aad = @mixed_ft.send(:build_aad, @mixed)
@mixed_aad.is_a?(String) && !@mixed_aad.empty?
#=> true

## Mixed fields - changing regular field changes AAD
@mixed2 = MixedAADModel.new(id: 'mixed-1', region: 'eu-west')
@mixed2.session_token = 'sess-abc123'
@mixed_aad2 = @mixed_ft.send(:build_aad, @mixed2)
@mixed_aad != @mixed_aad2
#=> true

## Mixed fields - changing transient field changes AAD
@mixed3 = MixedAADModel.new(id: 'mixed-1', region: 'us-east')
@mixed3.session_token = 'sess-xyz789'
@mixed_aad3 = @mixed_ft.send(:build_aad, @mixed3)
@mixed_aad != @mixed_aad3
#=> true

## Encrypt with transient field AAD succeeds
@record_enc = TransientAADModel.new(id: 'enc-transient-1')
@record_enc.passphrase = 'encryption-pass'
@record_enc.secret = 'my-secret-data'
@record_enc.secret.class.name
#=> "ConcealedString"

## Decrypt with unchanged transient field AAD succeeds
@decrypted = nil
@record_enc.secret.reveal { |pt| @decrypted = pt }
@decrypted
#=> "my-secret-data"

## Decrypt fails when transient field value changes
@record_tamper = TransientAADModel.new(id: 'tamper-1')
@record_tamper.passphrase = 'original-pass'
@record_tamper.secret = 'bound-secret'
@record_tamper.passphrase = 'tampered-pass'
@result = begin
  @record_tamper.secret.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'Familia::EncryptionError'
end
@result
#=> "Familia::EncryptionError"

## RedactedString cleared - getter returns nil, AAD uses empty value
# When passphrase is cleared, the transient field getter returns nil.
# build_aad uses nil.to_s (empty string) for the AAD computation.
# This is valid but will make the data undecryptable with the actual passphrase.
@record_cleared = TransientAADModel.new(id: 'cleared-1')
@record_cleared.passphrase = 'to-be-cleared'
@record_cleared.passphrase.clear!
@aad_cleared = @field_type.send(:build_aad, @record_cleared)
@aad_cleared.is_a?(String) && !@aad_cleared.empty?
#=> true

## Cleared passphrase AAD differs from the original passphrase AAD
@record_with_pass = TransientAADModel.new(id: 'cleared-1')
@record_with_pass.passphrase = 'to-be-cleared'
@aad_with_pass = @field_type.send(:build_aad, @record_with_pass)
@aad_cleared != @aad_with_pass
#=> true

## RedactedString value extraction works via build_aad_from_fields
@record_fromfields = TransientAADModel.new(id: 'fromfields-1')
@record_fromfields.passphrase = 'fromfields-pass'
@aad_fromfields = @field_type.send(:build_aad_from_fields, @record_fromfields, [:passphrase])
@aad_fromfields.is_a?(String) && !@aad_fromfields.empty?
#=> true

## build_aad and build_aad_from_fields produce same result for same fields
@record_compare = TransientAADModel.new(id: 'compare-1')
@record_compare.passphrase = 'compare-pass'
@aad_build = @field_type.send(:build_aad, @record_compare)
@aad_from = @field_type.send(:build_aad_from_fields, @record_compare, [:passphrase])
@aad_build == @aad_from
#=> true

Familia.dbclient.flushdb
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
