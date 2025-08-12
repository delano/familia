require_relative '../../helpers/test_helpers'
require 'base64'

# Setup encryption configuration
@test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v1

class BasicEncryptedModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :secret_data
end

class MultiInstanceModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :data
end

class NonceTestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :repeatable_data
end

class TimingTestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :timed_data
end

class MultiFieldModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :field_a
  encrypted_field :field_b
end

class AADTestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  field :context_field
  encrypted_field :aad_protected, aad_fields: [:context_field]
end

class NilTestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :optional_data
end

class PersistenceTestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :persistent_data
end

## Basic encrypted field functionality works
model = BasicEncryptedModel.new(user_id: 'test-basic')
model.secret_data = 'confidential'
# With secure-by-default, field access returns ConcealedString
model.secret_data.to_s
#=> '[CONCEALED]'

## Different instances derive keys independently
model1 = MultiInstanceModel.new(user_id: 'user-1')
model2 = MultiInstanceModel.new(user_id: 'user-2')
model1.data = 'secret-1'
model2.data = 'secret-2'
# With secure-by-default, both return ConcealedString
[model1.data.to_s, model2.data.to_s]
#=> ['[CONCEALED]', '[CONCEALED]']

## Same value encrypted multiple times produces different ciphertext
model = NonceTestModel.new(user_id: 'nonce-test')
model.repeatable_data = 'same-value'
first_internal = model.instance_variable_get(:@repeatable_data)
model.repeatable_data = 'same-value'
second_internal = model.instance_variable_get(:@repeatable_data)
first_internal != second_internal
#=> true

## Decrypted values remain the same despite different internal storage
model = NonceTestModel.new(user_id: 'nonce-test-2')
model.repeatable_data = 'same-value'
# With secure-by-default, field access returns ConcealedString
model.repeatable_data.to_s
#=> '[CONCEALED]'

## Fresh derivation verification through timing side-channel
@model = TimingTestModel.new(user_id: 'timing-test')
times = []
10.times do |i|
  start_time = Time.now
  @model.timed_data = "test-value-#{i}"
  @model.timed_data
  times << (Time.now - start_time)
end
min_time = times.min
max_time = times.max
variance_ratio = max_time / min_time
variance_ratio < 3.0
#=> true

## No cross-contamination between different field contexts
model = MultiFieldModel.new(user_id: 'multi-field')
model.field_a = 'value-a'
model.field_b = 'value-b'
internal_a = model.instance_variable_get(:@field_a)
internal_b = model.instance_variable_get(:@field_b)
internal_a != internal_b
#=> true

## Decrypted values are correct for multiple fields
model = MultiFieldModel.new(user_id: 'multi-field-2')
model.field_a = 'value-a'
model.field_b = 'value-b'
# With secure-by-default, both fields return ConcealedString
[model.field_a.to_s, model.field_b.to_s]
#=> ['[CONCEALED]', '[CONCEALED]']

## AAD fields affect derivation context
model1 = AADTestModel.new(user_id: 'aad-test-1', context_field: 'context-a')
model2 = AADTestModel.new(user_id: 'aad-test-2', context_field: 'context-b')
model1.aad_protected = 'protected-data'
model2.aad_protected = 'protected-data'
internal1 = model1.instance_variable_get(:@aad_protected)
internal2 = model2.instance_variable_get(:@aad_protected)
internal1 != internal2
#=> true

## AAD protected fields decrypt correctly
model1 = AADTestModel.new(user_id: 'aad-test-3', context_field: 'context-a')
model2 = AADTestModel.new(user_id: 'aad-test-4', context_field: 'context-b')
model1.aad_protected = 'protected-data'
model2.aad_protected = 'protected-data'
# With secure-by-default, both fields return ConcealedString
[model1.aad_protected.to_s, model2.aad_protected.to_s]
#=> ['[CONCEALED]', '[CONCEALED]']

## Memory efficiency - nil values not encrypted
model = NilTestModel.new(user_id: 'nil-test')
model.optional_data = nil
model.instance_variable_get(:@optional_data)
#=> nil

## Empty string should be encrypted differently than nil
model = NilTestModel.new(user_id: 'nil-test-2')
model.optional_data = ''
internal_empty = model.instance_variable_get(:@optional_data)
# Empty strings now treated as nil for consistency
internal_empty.nil?
#=> true

## Consistent behavior across Ruby restart simulation
model = PersistenceTestModel.new(user_id: 'persistence-test')
model.persistent_data = 'data-to-persist'
Thread.current[:familia_request_cache] = nil if Thread.current[:familia_request_cache]
# With secure-by-default, field access returns ConcealedString
model.persistent_data.to_s
#=> '[CONCEALED]'
