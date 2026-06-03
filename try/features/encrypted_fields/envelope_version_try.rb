# try/features/encrypted_fields/envelope_version_try.rb
#
# frozen_string_literal: true

# Tests for envelope versioning and backward compatibility.
# New envelopes include envelope_version: 2 and aad_fields array.
# Old envelopes (without these keys) fall back to class-level @aad_fields.
# Regression test for GitHub issue #280.

require 'base64'
require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Model with aad_fields for envelope tests
class EnvelopeVersionModel < Familia::Horreum
  feature :encrypted_fields

  identifier_field :id
  field :id
  field :org_id
  encrypted_field :secret, aad_fields: [:org_id]
end

# Model without aad_fields
class EnvelopeNoAADModel < Familia::Horreum
  feature :encrypted_fields

  identifier_field :id
  field :id
  encrypted_field :token
end

Familia.dbclient.flushdb

## New envelope has envelope_version: 2
@record = EnvelopeVersionModel.new(id: 'env-v2-1', org_id: 'org-abc')
@record.secret = 'versioned-secret'
@encrypted_json = @record.instance_variable_get(:@secret).encrypted_value
@envelope = Familia::JsonSerializer.parse(@encrypted_json)
@envelope['envelope_version']
#=> 2

## New envelope includes aad_fields array when aad_fields configured
@envelope['aad_fields']
#=> ["org_id"]

## New envelope without aad_fields does not include aad_fields key
@record_no_aad = EnvelopeNoAADModel.new(id: 'env-noaad-1')
@record_no_aad.token = 'no-aad-token'
@encrypted_json_noaad = @record_no_aad.instance_variable_get(:@token).encrypted_value
@envelope_noaad = Familia::JsonSerializer.parse(@encrypted_json_noaad)
@envelope_noaad['aad_fields']
#=> nil

## Envelope still has version 2 even without aad_fields
@envelope_noaad['envelope_version']
#=> 2

## Standard encryption fields present in envelope
@envelope.key?('algorithm')
#=> true

## Nonce present in envelope
@envelope.key?('nonce')
#=> true

## Ciphertext present in envelope
@envelope.key?('ciphertext')
#=> true

## Auth tag present in envelope
@envelope.key?('auth_tag')
#=> true

## Key version present in envelope
@envelope.key?('key_version')
#=> true

## Old envelope (no envelope_version) decrypts using class-level aad_fields
# Simulate an old envelope by manually creating one without envelope_version
@field_type = EnvelopeVersionModel.field_types[:secret]
@old_record = EnvelopeVersionModel.new(id: 'old-env-1', org_id: 'old-org')
@old_record.secret = 'old-format-secret'
@encrypted_old = @old_record.instance_variable_get(:@secret).encrypted_value
@old_envelope = Familia::JsonSerializer.parse(@encrypted_old)
@old_envelope.delete('envelope_version')
@old_envelope.delete('aad_fields')
@simulated_old = Familia::JsonSerializer.dump(@old_envelope)
@old_record.instance_variable_set(:@secret, nil)
@concealed = ConcealedString.new(@simulated_old, @old_record, @field_type)
@old_record.instance_variable_set(:@secret, @concealed)
@decrypted_old = nil
@old_record.secret.reveal { |pt| @decrypted_old = pt }
@decrypted_old
#=> "old-format-secret"

## Old envelope with different aad_fields still uses class-level fallback
class EvolvingModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :tenant
  field :region
  encrypted_field :config, aad_fields: [:tenant, :region]
end
@evolving_record = EvolvingModel.new(id: 'evolve-1', tenant: 'acme', region: 'us')
@evolving_record.config = 'evolved-config'
@encrypted_evolving = @evolving_record.instance_variable_get(:@config).encrypted_value
@evolving_envelope = Familia::JsonSerializer.parse(@encrypted_evolving)
@evolving_envelope['aad_fields'].sort
#=> ["region", "tenant"]

## Envelope version preserved through save/load cycle
@saved_record = EnvelopeVersionModel.new(id: 'save-load-1', org_id: 'saved-org')
@saved_record.secret = 'save-load-secret'
@saved_record.save
@loaded_record = EnvelopeVersionModel.load('save-load-1')
@encrypted_loaded = @loaded_record.instance_variable_get(:@secret).encrypted_value
@loaded_envelope = Familia::JsonSerializer.parse(@encrypted_loaded)
@loaded_envelope['envelope_version']
#=> 2

## aad_fields preserved through save/load cycle
@loaded_envelope['aad_fields']
#=> ["org_id"]

## Decrypt works after save/load with envelope metadata
@decrypted_loaded = nil
@loaded_record.secret.reveal { |pt| @decrypted_loaded = pt }
@decrypted_loaded
#=> "save-load-secret"

## Multiple aad_fields stored correctly in envelope
class MultiAADModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :org
  field :role
  field :env
  encrypted_field :credentials, aad_fields: [:org, :role, :env]
end
@multi = MultiAADModel.new(id: 'multi-1', org: 'acme', role: 'admin', env: 'prod')
@multi.credentials = 'multi-creds'
@multi_json = @multi.instance_variable_get(:@credentials).encrypted_value
@multi_env = Familia::JsonSerializer.parse(@multi_json)
@multi_env['aad_fields'].sort
#=> ["env", "org", "role"]

## Empty aad_fields array not stored in envelope
class EmptyAADModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :data, aad_fields: []
end
@empty_aad = EmptyAADModel.new(id: 'empty-aad-1')
@empty_aad.data = 'empty-aad-data'
@empty_json = @empty_aad.instance_variable_get(:@data).encrypted_value
@empty_env = Familia::JsonSerializer.parse(@empty_json)
@empty_env['aad_fields']
#=> nil

Familia.dbclient.flushdb
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
