# try/features/encryption/envelope_encoding_validation_try.rb
#
# frozen_string_literal: true

# The envelope's `encoding` field is applied to the decrypted plaintext with
# force_encoding but is not covered by the AEAD tag. Before #408 it was also
# never validated, so a rewritten value either silently retagged the bytes
# (a valid-but-wrong name) or raised ArgumentError/TypeError that the generic
# rescue in Manager#decrypt reported as "Decryption failed", indistinguishable
# from corrupted ciphertext. These tests pin the allowlist that closes that.
# See: https://github.com/delano/familia/issues/408

require 'base64'
require_relative '../../support/helpers/test_helpers'

set_test_encryption_keys({ v1: Base64.strict_encode64('a' * 32) }, current_version: :v1)

class EncodingValidationModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

@context = 'EncodingValidationModel:secret:enc-1'
@envelope = Familia::Encryption.encrypt('hello', context: @context)
@parsed = Familia::JsonSerializer.parse(@envelope, symbolize_names: true)

# Rewrite only the encoding field; everything under the auth tag stays intact.
def with_encoding(parsed, value)
  Familia::JsonSerializer.dump(parsed.merge(encoding: value))
end

## The allowlist excludes the host-dependent pseudo names
(Familia::Encryption::ENVELOPE_ENCODINGS & %w[locale external internal filesystem])
#=> []

## The allowlist includes every canonical name the write path can record
%w[UTF-8 ASCII-8BIT US-ASCII ISO-8859-1].all? do |name|
  Familia::Encryption::ENVELOPE_ENCODINGS.include?(name)
end
#=> true

## An unknown encoding name is a defined EncryptionError
Familia::Encryption.decrypt(with_encoding(@parsed, 'bogus-encoding'), context: @context)
#=!> Familia::EncryptionError
#==> error.message.include?('Unsupported encoding')

## The defined error no longer carries the swallowed ArgumentError text
Familia::Encryption.decrypt(with_encoding(@parsed, 'bogus-encoding'), context: @context)
#=!> Familia::EncryptionError
#==> !error.message.include?('unknown encoding name')

## A non-string encoding is rejected the same way (previously a swallowed TypeError)
Familia::Encryption.decrypt(with_encoding(@parsed, 123), context: @context)
#=!> Familia::EncryptionError
#==> error.message.include?('Unsupported encoding')

## A host-dependent pseudo name is rejected even though Ruby resolves it
Familia::Encryption.decrypt(with_encoding(@parsed, 'locale'), context: @context)
#=!> Familia::EncryptionError
#==> error.message.include?('Unsupported encoding')

## Rejection happens before any key derivation work
before = Familia::Encryption.derivation_count.value
begin
  Familia::Encryption.decrypt(with_encoding(@parsed, 'bogus-encoding'), context: @context)
rescue Familia::EncryptionError
  nil
end
# Only the attempt counter increment at the top of #decrypt, no derive_key.
Familia::Encryption.derivation_count.value - before
#=> 1

## The Hash form of the envelope is validated too
Familia::Encryption.decrypt(@parsed.merge(encoding: 'bogus-encoding'), context: @context)
#=!> Familia::EncryptionError
#==> error.message.include?('Unsupported encoding')

## A known alias is accepted and resolves to its encoding
Familia::Encryption.decrypt(with_encoding(@parsed, 'BINARY'), context: @context).encoding.name
#=> "ASCII-8BIT"

## An envelope without an encoding field still decrypts as UTF-8
@legacy = Familia::JsonSerializer.dump(@parsed.reject { |k, _| k == :encoding })
Familia::Encryption.decrypt(@legacy, context: @context).encoding.name
#=> "UTF-8"

## An untouched envelope still round-trips
Familia::Encryption.decrypt(@envelope, context: @context)
#=> "hello"

## EncryptedData#decryptable? is false for an unknown encoding
Familia::Encryption::EncryptedData.from_json(with_encoding(@parsed, 'bogus-encoding')).decryptable?
#=> false

## EncryptedData#decryptable? stays true for a known encoding
Familia::Encryption::EncryptedData.from_json(@envelope).decryptable?
#=> true

## EncryptedData#validate_decryptable! raises for an unknown encoding
Familia::Encryption::EncryptedData.from_json(with_encoding(@parsed, 'bogus-encoding')).validate_decryptable!
#=!> Familia::EncryptionError
#==> error.message.include?('Unsupported encoding')

## EncryptedData#validate_decryptable! returns self for a known encoding
data = Familia::Encryption::EncryptedData.from_json(@envelope)
data.validate_decryptable!.equal?(data)
#=> true

## EncryptedData#encoding_valid? treats a missing encoding as valid
Familia::Encryption::EncryptedData.from_json(@legacy).encoding_valid?
#=> true

## A stored envelope with a tampered encoding is rejected when the field is wrapped
@record = EncodingValidationModel.new(id: 'enc-1')
@record.secret = 'hello'
@record.save
tampered = with_encoding(
  Familia::JsonSerializer.parse(@record.secret.encrypted_value, symbolize_names: true), 'bogus-encoding'
)
EncodingValidationModel.dbclient.hset(EncodingValidationModel.dbkey('enc-1'), 'secret', tampered)
@loaded = EncodingValidationModel.find_by_id('enc-1')
@loaded.secret
#=!> Familia::EncryptionError
#==> error.message.include?('Unsupported encoding')

## The untampered record still reveals through the same path
@record.secret! 'hello'
EncodingValidationModel.find_by_id('enc-1').secret.reveal { |plain| plain }
#=> "hello"

# TEARDOWN
EncodingValidationModel.dbclient.del(EncodingValidationModel.dbkey('enc-1'))
clear_test_encryption_keys
