# try/features/encrypted_fields/fast_writer_try.rb
#
# frozen_string_literal: true

# Tests the fast writer path (model.field_name! 'value') for encrypted fields.
# Verifies immediate persistence, nil guard, and equivalence with normal setter.

require 'base64'
require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class EncryptedFastWriterModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

Familia.dbclient.flushdb

## Fast write persists and can be revealed after reload
record = EncryptedFastWriterModel.new(id: 'fast-1')
record.save
record.secret! 'fast-value'
reloaded = EncryptedFastWriterModel.load('fast-1')
decrypted = nil
reloaded.secret.reveal { |pt| decrypted = pt }
decrypted
#=> "fast-value"

## Fast write with nil raises ArgumentError
record2 = EncryptedFastWriterModel.new(id: 'fast-2')
record2.save
result = begin
  record2.secret! nil
  'UNEXPECTED SUCCESS'
rescue ArgumentError => e
  e.class.name
end
result
#=> "ArgumentError"

## Fast write and normal setter produce equivalent decryptable results
record_fast = EncryptedFastWriterModel.new(id: 'fast-3')
record_fast.save
record_fast.secret! 'shared-value'

record_normal = EncryptedFastWriterModel.new(id: 'normal-3')
record_normal.secret = 'shared-value'
record_normal.save

loaded_fast = EncryptedFastWriterModel.load('fast-3')
loaded_normal = EncryptedFastWriterModel.load('normal-3')

decrypted_fast = nil
decrypted_normal = nil
loaded_fast.secret.reveal { |pt| decrypted_fast = pt }
loaded_normal.secret.reveal { |pt| decrypted_normal = pt }
decrypted_fast == decrypted_normal && decrypted_fast == 'shared-value'
#=> true

Familia.dbclient.flushdb
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
