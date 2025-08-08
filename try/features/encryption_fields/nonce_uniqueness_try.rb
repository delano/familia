# try/features/encryption_fields/nonce_uniqueness_try.rb

require 'base64'
require 'set'

require_relative '../../helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class NonceTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

## Multiple encryptions produce unique nonces
model = NonceTest.new(id: 'nonce-test')
nonces = Set.new

10.times do
  model.secret = 'same-value'
  cipher = JSON.parse(model.instance_variable_get(:@secret))
  nonces.add(cipher['nonce'])
end

nonces.size == 10
#=> true

## Each encryption generates a unique nonce even for identical data
@model2 = NonceTest.new(id: 'nonce-test-2')

# Encrypt same value twice
@model2.secret = 'duplicate-test'
@cipher1 = JSON.parse(@model2.instance_variable_get(:@secret))

@model2.secret = 'duplicate-test'
@cipher2 = JSON.parse(@model2.instance_variable_get(:@secret))

# Nonces should be different
@cipher1['nonce'] != @cipher2['nonce']
#=> true

## Ciphertexts are also different due to different nonces
@cipher1['ciphertext'] != @cipher2['ciphertext']
#=> true

# Cleanup
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
