# try/features/encryption_fields/context_isolation_try.rb

require 'base64'

require_relative '../../helpers/test_helpers'

# Setup encryption keys for testing
test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class IsolationUser < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :secret
end

# Different models with same field name have isolated contexts
class ModelA < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

class ModelB < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

## Different user IDs produce different ciphertexts for same plaintext
@user1 = IsolationUser.new(user_id: 'alice')
@user2 = IsolationUser.new(user_id: 'bob')

@user1.secret = 'shared-secret'
@user2.secret = 'shared-secret'

@cipher1 = @user1.instance_variable_get(:@secret)
@cipher2 = @user2.instance_variable_get(:@secret)

@cipher1 != @cipher2
#=> true

## Same plaintext decrypts correctly for both users - access via refinement
@user1_decrypted = nil
module User1TestAccess
  using ConcealedStringTestHelper
  user1 = IsolationUser.new(user_id: 'alice')
  user1.secret = 'shared-secret'
  user1.secret.reveal_for_testing
end
#=> 'shared-secret'

## Test user2 isolation
@user2_decrypted = nil
module User2TestAccess
  using ConcealedStringTestHelper
  user2 = IsolationUser.new(user_id: 'bob')
  user2.secret = 'shared-secret'
  user2.secret.reveal_for_testing
end
#=> 'shared-secret'

## Different model classes have isolated encryption contexts
@model_a = ModelA.new(id: 'same-id')
@model_b = ModelB.new(id: 'same-id')

@model_a.api_key = 'secret-key'
@model_b.api_key = 'secret-key'

@cipher_a = @model_a.instance_variable_get(:@api_key)
@cipher_b = @model_b.instance_variable_get(:@api_key)

@cipher_a != @cipher_b
#=> true

## Model A can decrypt its own data - access via refinement
module ModelATestAccess
  using ConcealedStringTestHelper
  model_a = ModelA.new(id: 'same-id')
  model_a.api_key = 'secret-key'
  model_a.api_key.reveal_for_testing
end
#=> 'secret-key'

## Model B can decrypt its own data - access via refinement
module ModelBTestAccess
  using ConcealedStringTestHelper
  model_b = ModelB.new(id: 'same-id')
  model_b.api_key = 'secret-key'
  model_b.api_key.reveal_for_testing
end
#=> 'secret-key'

## Cross-model decryption fails due to context mismatch
@model_a.instance_variable_set(:@api_key, @cipher_b)
begin
  @model_a.api_key
  false
rescue Familia::EncryptionError
  true
end
#=> true

## Different field names in same model create different contexts
class MultiFieldModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :field_one
  encrypted_field :field_two
end

@multi = MultiFieldModel.new(id: 'test')
@multi.field_one = 'same-value'
@multi.field_two = 'same-value'

@cipher_field1 = @multi.instance_variable_get(:@field_one)
@cipher_field2 = @multi.instance_variable_get(:@field_two)

@cipher_field1 != @cipher_field2
#=> true

## Cross-field decryption fails due to field context isolation
@multi.instance_variable_set(:@field_one, @cipher_field2)
begin
  @multi.field_one
  false
rescue Familia::EncryptionError
  true
end
#=> true

# Cleanup
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
