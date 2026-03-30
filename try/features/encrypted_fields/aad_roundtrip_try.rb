# try/features/encrypted_fields/aad_roundtrip_try.rb
#
# frozen_string_literal: true

# Verifies that encrypted fields with aad_fields survive the
# create! -> reveal and create! -> load -> reveal round-trips.
# Regression test for GitHub issue #232.

require 'base64'
require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class AADRoundtripModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :domain_id
  field :domain_id
  field :email
  encrypted_field :api_key, aad_fields: [:domain_id]
end

class AADRoundtripEnforcementModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :email
  encrypted_field :api_key, aad_fields: [:email]
end

Familia.dbclient.flushdb

## reveal succeeds on in-memory object after create! with aad_fields
config = AADRoundtripModel.create!(domain_id: 'dom-001', api_key: 'secret-abc')
decrypted = nil
config.api_key.reveal { |pt| decrypted = pt }
decrypted
#=> "secret-abc"

## reveal succeeds on object reloaded from Redis after create!
config2 = AADRoundtripModel.create!(domain_id: 'dom-002', api_key: 'secret-xyz')
reloaded = AADRoundtripModel.load('dom-002')
decrypted2 = nil
reloaded.api_key.reveal { |pt| decrypted2 = pt }
decrypted2
#=> "secret-xyz"

## build_aad produces identical AAD before and after save
unsaved = AADRoundtripModel.new(domain_id: 'dom-003', email: 'test@example.com')
field_type = AADRoundtripModel.field_types[:api_key]
aad_before = field_type.send(:build_aad, unsaved)
unsaved.save
aad_after = field_type.send(:build_aad, unsaved)
aad_before == aad_after
#=> true

## round-trip works with new + manual save pattern
manual = AADRoundtripModel.new(domain_id: 'dom-004')
manual.api_key = 'manual-secret'
manual.save
decrypted3 = nil
manual.api_key.reveal { |pt| decrypted3 = pt }
decrypted3
#=> "manual-secret"

## round-trip works with new + save + load pattern
manual2 = AADRoundtripModel.new(domain_id: 'dom-005')
manual2.api_key = 'reload-secret'
manual2.save
reloaded2 = AADRoundtripModel.load('dom-005')
decrypted4 = nil
reloaded2.api_key.reveal { |pt| decrypted4 = pt }
decrypted4
#=> "reload-secret"

## AAD fields are enforced on unsaved records - unchanged field decrypts successfully
unsaved2 = AADRoundtripEnforcementModel.new(id: 'enforce-1', email: 'stable@example.com')
unsaved2.api_key = 'bound-secret'
decrypted5 = nil
unsaved2.api_key.reveal { |pt| decrypted5 = pt }
decrypted5
#=> "bound-secret"

## AAD fields are enforced on unsaved records - changed field breaks reveal
unsaved3 = AADRoundtripEnforcementModel.new(id: 'enforce-2', email: 'original@example.com')
unsaved3.api_key = 'enforced-secret'
unsaved3.email = 'tampered@example.com'
result_enforced = begin
  unsaved3.api_key.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'Familia::EncryptionError'
end
result_enforced
#=> "Familia::EncryptionError"

Familia.dbclient.flushdb
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
