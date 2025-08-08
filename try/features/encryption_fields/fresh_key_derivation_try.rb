# try/features/encryption_fields/fresh_key_derivation_try.rb

require 'base64'

require_relative '../../helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class FreshKeyDerivationTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

## Single encrypt operation increments counter
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-encrypt-1')
model.test_field = 'test-value'
Familia::Encryption.derivation_count.value
#=> 1

## Single decrypt operation increments counter again
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-decrypt-1')
model.test_field = 'test-value'  # encrypt (1 derivation)
retrieved = model.test_field     # decrypt (2 derivations)
[retrieved, Familia::Encryption.derivation_count.value]
#=> ['test-value', 2]

## Multiple encrypt operations accumulate derivation calls
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-encrypt-multi')
3.times { |i| model.test_field = "value-#{i}" }
Familia::Encryption.derivation_count.value
#=> 3

## Multiple decrypt operations call derivation each time
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-decrypt-multi')
model.test_field = 'initial-value'
3.times { model.test_field }
Familia::Encryption.derivation_count.value
#=> 4

## Mixed encrypt/decrypt operations accumulate calls
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-mixed')
2.times { |i| model.test_field = "mixed-#{i}" }  # 2 encryptions
2.times { model.test_field }                     # 2 decryptions
Familia::Encryption.derivation_count.value
#=> 4

## Write-read pairs trigger derivation for each operation
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-pairs')
results = []
5.times do |i|
  model.test_field = "pair-#{i}"  # encrypt
  results << model.test_field     # decrypt
end
[results.length, Familia::Encryption.derivation_count.value]
#=> [5, 10]

## Different field values trigger fresh derivation each time
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-different-values')
model.test_field = 'first'
first_count = Familia::Encryption.derivation_count.value
model.test_field = 'second'
second_count = Familia::Encryption.derivation_count.value
model.test_field = 'third'
third_count = Familia::Encryption.derivation_count.value
[first_count, second_count, third_count]
#=> [1, 2, 3]

## Verify no caching occurs across operations
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-no-cache')
values = ['alpha', 'beta', 'gamma']
operation_pairs = values.map do |val|
  model.test_field = val        # encrypt
  retrieved = model.test_field  # decrypt
  [val, retrieved]
end
all_match = operation_pairs.all? { |pair| pair[0] == pair[1] }
[all_match, Familia::Encryption.derivation_count.value]
#=> [true, 6]

## Empty string handling doesn't trigger derivation
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-empty')
model.test_field = ''
empty_result = model.test_field
[empty_result, Familia::Encryption.derivation_count.value]
#=> [nil, 0]

## Nil values don't trigger derivation
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-nil')
model.test_field = nil
nil_result = model.test_field
[nil_result, Familia::Encryption.derivation_count.value]
#=> [nil, 0]

Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
