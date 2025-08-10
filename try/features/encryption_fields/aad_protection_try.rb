# try/features/encryption_fields/aad_protection_try.rb

require 'concurrent'
require 'base64'

require_relative '../../helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class AADProtectedModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :email
  encrypted_field :api_key, aad_fields: [:email]
end

## AAD prevents field substitution attacks when record exists
model = AADProtectedModel.new(id: 'aad-1', email: 'user@example.com')
model.save  # Need to save first for AAD to be active
model.api_key = 'secret-key'
model.save  # Save the encrypted value
ciphertext = model.instance_variable_get(:@api_key)

# Change AAD field after encryption
model.email = 'attacker@evil.com'
model.instance_variable_set(:@api_key, ciphertext)
model.api_key
#=!> Familia::EncryptionError
#==> error.message.include?('Decryption failed')

## Without saving, AAD is not enforced (returns nil)
unsaved_model = AADProtectedModel.new(id: 'aad-2', email: 'test@example.com')
unsaved_model.api_key = 'test-key'
stored = unsaved_model.instance_variable_get(:@api_key)
# Change email and it still decrypts (no AAD protection without save)
unsaved_model.email = 'changed@example.com'
unsaved_model.instance_variable_set(:@api_key, stored)
unsaved_model.api_key
#=> 'test-key'

# Cleanup
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
