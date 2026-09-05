# try/features/encrypted_fields/identifier_precondition_try.rb
#
# frozen_string_literal: true

# Encryption contexts include the record identifier. Encrypting before the
# identifier exists must fail rather than create ciphertext that becomes
# undecryptable when an identifier is assigned later.

require 'base64'
require_relative '../../support/helpers/test_helpers'

set_test_encryption_keys({ v1: Base64.strict_encode64('a' * 32) },
                         current_version: :v1)

# Fixture for encrypted-field identifier precondition coverage.
class EncryptionIdentifierPreconditionModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :record_id
  field :record_id
  encrypted_field :secret
end

# Declares context dependencies after the encrypted field to verify keyword
# construction is independent of model field declaration order.
EncryptionDeclarationOrderModel = Class.new(Familia::Horreum) do
  feature :encrypted_fields
  identifier_field :record_id
  encrypted_field :secret, aad_fields: [:scope]
  field :scope
  field :record_id
end

## Assigning plaintext without an identifier raises NoIdentifier before encryption
Familia::Encryption.reset_derivation_count!
@missing_id = EncryptionIdentifierPreconditionModel.new
@missing_id.secret = 'classified'
#=!> Familia::NoIdentifier
#==> error.message.include?("Cannot encrypt 'secret'")

## A rejected assignment neither stores a value nor derives a key
[@missing_id.secret, Familia::Encryption.derivation_count.value]
#=> [nil, 0]

## An empty identifier is rejected like a nil identifier
@empty_id = EncryptionIdentifierPreconditionModel.new(record_id: '')
@empty_id.secret = 'classified'
#=!> Familia::NoIdentifier

## Keyword construction cannot encrypt a field without an identifier
EncryptionIdentifierPreconditionModel.new(secret: 'classified')
#=!> Familia::NoIdentifier

## Assignment succeeds and remains decryptable after the identifier is assigned
@missing_id.record_id = 'record-1'
@missing_id.secret = 'classified'
@missing_id.secret.reveal { |plaintext| plaintext }
#=> 'classified'

## Keyword construction initializes context dependencies before encrypted fields
@declaration_order = EncryptionDeclarationOrderModel.new(
  secret: 'constructor-secret',
  record_id: 'record-2',
  scope: 'account-1',
)
[@declaration_order.identifier, @declaration_order.secret.reveal { |plaintext| plaintext }]
#=> ['record-2', 'constructor-secret']

## Constructor ciphertext remains bound to AAD declared after the encrypted field
@declaration_order.scope = 'account-2'
@declaration_order.secret.reveal { |plaintext| plaintext }
#=!> Familia::EncryptionError

## Nil and empty values still clear the field without requiring an identifier
@clear_only = EncryptionIdentifierPreconditionModel.new
@clear_only.secret = nil
@clear_only.secret = ''
@clear_only.secret
#=> nil

clear_test_encryption_keys
