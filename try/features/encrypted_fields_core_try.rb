# try/features/encrypted_fields_core_try.rb

require_relative '../helpers/test_helpers'
require 'base64'


## Encrypted field methods are properly defined
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecureUser < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id

  field :user_id
  field :email
  encrypted_field :ssn
  encrypted_field :api_key, aad_fields: [:email]
end

user = SecureUser.new(user_id: 'test-user-001', email: 'test@example.com')
user.respond_to?(:ssn) && user.respond_to?(:ssn=)
#=> true

## Setting encrypted field stores ConcealedString (secure by default)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecureUser2 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :ssn
end

user = SecureUser2.new(user_id: 'test-user-002')
user.ssn = '123-45-6789'
stored_value = user.instance_variable_get(:@ssn)
stored_value.class.name == "ConcealedString"
#=> true

## Getter returns ConcealedString (secure by default)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecureUserDecrypt < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :ssn
end

@user = SecureUserDecrypt.new(user_id: 'decrypt-test')
@user.ssn = '123-45-6789'
@user.ssn.to_s
#=> '[CONCEALED]'

## Controlled decryption with reveal block
@user.ssn.reveal { |decrypted| decrypted }
#=> '123-45-6789'

## repaired test
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecureUser3 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :ssn
end

user = SecureUser3.new(user_id: 'test-user-003')
user.ssn = nil
result = user.instance_variable_get(:@ssn)
user.ssn.nil? && result.nil?
#=> true

## Field type is correctly identified as encrypted
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecureUser4 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :ssn
end

field_type = SecureUser4.field_types[:ssn]
field_type.category
#=> :encrypted

## Field type is persistent
SecureUser4.field_types[:ssn].persistent?
#=> true

## Encrypted field with AAD fields configured (secure by default)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecureUser5 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  field :email
  encrypted_field :api_key, aad_fields: [:email]
end

@user2 = SecureUser5.new(user_id: 'test-user-005', email: 'test@example.com')
@user2.api_key = 'secret-key-123'
@user2.api_key.to_s
#=> '[CONCEALED]'

## AAD fields work with controlled decryption
@user2.api_key.reveal { |decrypted| decrypted }
#=> 'secret-key-123'

Thread.current[:familia_key_cache]&.clear if Thread.current[:familia_key_cache]
