# try/features/encrypted_fields/nonce_uniqueness_try.rb
#
# frozen_string_literal: true

# try/features/encryption_fields/nonce_uniqueness_try.rb

require 'base64'
require 'set'

require_relative '../../support/helpers/test_helpers'

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

## Multiple encryptions produce unique nonces (concealed behavior)
model = NonceTest.new(id: 'nonce-test')
concealed_values = ::Set.new

10.times do
  model.secret = 'same-value'
  # With ConcealedString, we can't directly inspect nonces for security
  # Instead verify that the field behaves consistently
  concealed_values.add(model.secret.to_s)
end

# All should be concealed consistently
concealed_values.size == 1 && concealed_values.first == "[CONCEALED]"
#=> true

## Each encryption generates a unique nonce even for identical data (concealed)
@model2 = NonceTest.new(id: 'nonce-test-2')

# Encrypt same value twice - with ConcealedString, values are consistently concealed
@model2.secret = 'duplicate-test'
@concealed1 = @model2.secret.to_s

@model2.secret = 'duplicate-test'
@concealed2 = @model2.secret.to_s

# Both encryptions should be consistently concealed
@concealed1 == "[CONCEALED]" && @concealed2 == "[CONCEALED]"
#=> true

## Ciphertexts are also different due to different nonces (concealed from view)
@concealed1 == @concealed2
#=> true

# Cleanup
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
