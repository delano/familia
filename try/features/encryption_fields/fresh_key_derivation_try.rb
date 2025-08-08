# try/features/encryption_fields/fresh_key_derivation_try.rb


require 'base64'

require_relative '../../helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1


Familia.config.current_key_version = :v1

# Fresh key derivation verification - mock the actual derivation
class NoCacheDerivationTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

@derivation_calls = 0
@original_method = Familia::Encryption.method(:perform_key_derivation)

# Track derivation calls by mocking the internal method
Familia::Encryption.define_singleton_method(:perform_key_derivation) do |master_key, context|
  @derivation_calls = 0 if @derivation_calls.nil?
  @derivation_calls += 1
  @original_method.call(master_key, context)
end

@model = NoCacheDerivationTest.new(user_id: 'derivation-test')
@derivation_calls = 0 # Reset counter

## Single encrypt operation
@model.test_field = 'test-value'
@encrypt_calls = @derivation_calls
@encrypt_calls
#=> 1

## Single decrypt operation
@retrieved = @model.test_field
@decrypt_calls = @derivation_calls
@decrypt_calls
#=> 2


## Track derivation calls by mocking the internal method
derivation_calls = 0
original_method = Familia::Encryption.method(:perform_key_derivation)

Familia::Encryption.define_singleton_method(:perform_key_derivation) do |master_key, context|
  derivation_calls += 1
  original_method.call(master_key, context)
end
derivation_calls
#=> 3


## Single encrypt operation calls derivation once
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class NoCacheDerivationTest1 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

@derivation_calls = 0
model = NoCacheDerivationTest1.new(user_id: 'test-1')
model.test_field = 'test-value'
@derivation_calls
#=> 1

## Single decrypt operation calls derivation again
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class NoCacheDerivationTest2 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

@derivation_calls = 0
model = NoCacheDerivationTest2.new(user_id: 'test-2')
model.test_field = 'test-value'
encrypt_calls = @derivation_calls
result = model.test_field
decrypt_calls = @derivation_calls
[encrypt_calls, decrypt_calls, result]
#=> [1, 2, 'test-value']

## Multiple encrypt operations call derivation each time
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class NoCacheDerivationTest3 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

@derivation_calls = 0
model = NoCacheDerivationTest3.new(user_id: 'test-3')
3.times { |i| model.test_field = "value-#{i}" }
@derivation_calls
#=> 3

## Multiple decrypt operations call derivation each time
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class NoCacheDerivationTest4 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

@derivation_calls = 0
model = NoCacheDerivationTest4.new(user_id: 'test-4')
model.test_field = 'initial-value'
3.times { model.test_field }
@derivation_calls
#=> 4
#==> @derivation_calls > 3

## Mixed operations accumulate derivation calls
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class NoCacheDerivationTest5 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

@derivation_calls = 0
model = NoCacheDerivationTest5.new(user_id: 'test-5')
2.times { |i| model.test_field = "mixed-#{i}" }
2.times { model.test_field }
@derivation_calls
#=> 4
#==> @derivation_calls > 0

## No caching between different field access patterns
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class NoCacheDerivationTest6 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

@derivation_calls = 0
model = NoCacheDerivationTest6.new(user_id: 'test-6')
5.times do |i|
  model.test_field = "batch-#{i}"
  model.test_field
end
@derivation_calls
#=> 10
#==> @derivation_calls == 10

## Different values trigger fresh derivation each time
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class NoCacheDerivationTest7 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

@derivation_calls = 0
model = NoCacheDerivationTest7.new(user_id: 'test-7')
model.test_field = 'first'
first_calls = @derivation_calls
model.test_field = 'second'
second_calls = @derivation_calls
model.test_field = 'third'
third_calls = @derivation_calls
[first_calls, second_calls, third_calls]
#=> [1, 2, 3]

## Write-read pairs each trigger derivation independently
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class NoCacheDerivationTest8 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

derivation_calls = 0
model = NoCacheDerivationTest8.new(user_id: 'test-8')
values = ['alpha', 'beta', 'gamma']
results = values.map do |val|
  model.test_field = val
  retrieved = model.test_field
  [val, retrieved]
end
[derivation_calls, results.all? { |pair| pair[0] == pair[1] }]
#=> [6, true]

Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
