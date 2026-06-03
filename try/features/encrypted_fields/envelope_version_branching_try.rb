# try/features/encrypted_fields/envelope_version_branching_try.rb
#
# frozen_string_literal: true

# Tests that decrypt_value branches on envelope_version:
# - v2 envelopes use stored aad_fields and key_material_fields
# - Old envelopes (no version) fall back to class-level @aad_fields
#   and never apply key_material, even if the field type has one configured.

require 'base64'
require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class VersionBranchModel < Familia::Horreum
  feature :encrypted_fields

  identifier_field :id
  field :id
  field :org_id
  encrypted_field :secret, aad_fields: [:org_id]
end

class VersionBranchKMModel < Familia::Horreum
  feature :encrypted_fields

  identifier_field :id
  field :id
  field :salt
  encrypted_field :vault, key_material: ->(r) { r.salt }
end

Familia.dbclient.flushdb

## v2 envelope decrypts normally
@record = VersionBranchModel.new(id: 'vb-1', org_id: 'org-a')
@record.secret = 'v2-secret'
@decrypted = nil
@record.secret.reveal { |pt| @decrypted = pt }
@decrypted
#=> "v2-secret"

## Stripping envelope_version from v2 envelope still decrypts (backward compat path)
@ft = VersionBranchModel.field_types[:secret]
@record2 = VersionBranchModel.new(id: 'vb-2', org_id: 'org-b')
@record2.secret = 'strip-version'
@encrypted_json = @record2.instance_variable_get(:@secret).encrypted_value
@envelope = Familia::JsonSerializer.parse(@encrypted_json)
@envelope.delete('envelope_version')
@envelope.delete('aad_fields')
@stripped_json = Familia::JsonSerializer.dump(@envelope)
@decrypted_stripped = @ft.decrypt_value(@record2, @stripped_json)
@decrypted_stripped
#=> "strip-version"

## Old envelope ignores key_material even when field type has it configured
@km_ft = VersionBranchKMModel.field_types[:vault]
@km_record = VersionBranchKMModel.new(id: 'vb-km-1', salt: 'my-salt')
@km_record.vault = 'km-secret'
@km_json = @km_record.instance_variable_get(:@vault).encrypted_value
@km_envelope = Familia::JsonSerializer.parse(@km_json)
@km_envelope.delete('envelope_version')
@km_envelope.delete('key_material_fields')
@old_km_json = Familia::JsonSerializer.dump(@km_envelope)
# This should fail: the data was encrypted WITH key_material but the
# old-envelope path does not apply it. Decrypt produces garbage → EncryptionError.
@km_result = begin
  @km_ft.decrypt_value(@km_record, @old_km_json)
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'Familia::EncryptionError'
end
@km_result
#=> "Familia::EncryptionError"

## v2 envelope with key_material decrypts when key_material is correct
@km_record2 = VersionBranchKMModel.new(id: 'vb-km-2', salt: 'correct-salt')
@km_record2.vault = 'km-roundtrip'
@km_decrypted = nil
@km_record2.vault.reveal { |pt| @km_decrypted = pt }
@km_decrypted
#=> "km-roundtrip"

## v2 envelope with stored aad_fields survives save/load cycle
@saved = VersionBranchModel.new(id: 'vb-save-1', org_id: 'saved-org')
@saved.secret = 'persist-me'
@saved.save
@loaded = VersionBranchModel.load('vb-save-1')
@loaded_pt = nil
@loaded.secret.reveal { |pt| @loaded_pt = pt }
@loaded_pt
#=> "persist-me"

## v2 loaded envelope still has version 2
@loaded_json = @loaded.instance_variable_get(:@secret).encrypted_value
@loaded_env = Familia::JsonSerializer.parse(@loaded_json)
@loaded_env['envelope_version']
#=> 2

Familia.dbclient.flushdb
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
