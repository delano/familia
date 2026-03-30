# try/features/encrypted_fields/aad_nil_fields_try.rb
#
# frozen_string_literal: true

# Verifies build_aad behavior when AAD field values are nil or empty.
# Covers edge cases around nil vs empty string AAD consistency.

require 'base64'
require 'digest'
require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class AADNilFieldModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :email
  encrypted_field :api_key, aad_fields: [:email]
end

Familia.dbclient.flushdb

## Encrypt with nil AAD field and reveal without changing it succeeds
record = AADNilFieldModel.new(id: 'nil-aad-1')
record.api_key = 'nil-aad-secret'
decrypted = nil
record.api_key.reveal { |pt| decrypted = pt }
decrypted
#=> "nil-aad-secret"

## Encrypt with nil AAD field then set field to non-nil causes reveal to fail
record2 = AADNilFieldModel.new(id: 'nil-aad-2')
record2.api_key = 'bound-to-nil'
record2.email = 'now-set@example.com'
result = begin
  record2.api_key.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'Familia::EncryptionError'
end
result
#=> "Familia::EncryptionError"

## Encrypt with non-nil AAD field then set to nil causes reveal to fail
record3 = AADNilFieldModel.new(id: 'nil-aad-3', email: 'was-set@example.com')
record3.api_key = 'bound-to-email'
record3.email = nil
result3 = begin
  record3.api_key.reveal { |pt| pt }
  'UNEXPECTED SUCCESS'
rescue Familia::EncryptionError
  'Familia::EncryptionError'
end
result3
#=> "Familia::EncryptionError"

## Encrypt with empty string AAD field and reveal succeeds
# Note: the setter treats empty string as nil for the encrypted field itself,
# but the AAD field (email) is a regular field that can hold empty string.
record4 = AADNilFieldModel.new(id: 'nil-aad-4', email: '')
record4.api_key = 'empty-email-secret'
decrypted4 = nil
record4.api_key.reveal { |pt| decrypted4 = pt }
decrypted4
#=> "empty-email-secret"

## nil and empty string AAD fields produce different AAD values
record_nil = AADNilFieldModel.new(id: 'aad-cmp-1')
record_empty = AADNilFieldModel.new(id: 'aad-cmp-1', email: '')
field_type = AADNilFieldModel.field_types[:api_key]
aad_nil = field_type.send(:build_aad, record_nil)
aad_empty = field_type.send(:build_aad, record_empty)
aad_nil != aad_empty
#=> true

Familia.dbclient.flushdb
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
