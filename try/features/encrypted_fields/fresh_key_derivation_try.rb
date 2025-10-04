# try/features/encryption_fields/fresh_key_derivation_try.rb

require 'base64'

require_relative '../../support/helpers/test_helpers'

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
retrieved = model.test_field     # returns ConcealedString (no decrypt yet)
# With secure-by-default, direct access doesn't trigger decryption
[retrieved.to_s, Familia::Encryption.derivation_count.value]
#=> ['[CONCEALED]', 1]

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
# With secure-by-default, field access returns ConcealedString, no decryption
3.times { model.test_field }
Familia::Encryption.derivation_count.value
#=> 1

## Mixed encrypt/decrypt operations accumulate calls
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-mixed')
2.times { |i| model.test_field = "mixed-#{i}" }  # 2 encryptions
2.times { model.test_field }                     # ConcealedString access (no decryption)
Familia::Encryption.derivation_count.value
#=> 2

## Write-read pairs trigger derivation for each operation
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-pairs')
results = []
5.times do |i|
  model.test_field = "pair-#{i}"  # encrypt
  results << model.test_field     # ConcealedString (no decrypt)
end
# With secure-by-default, only encryptions trigger derivation
[results.length, Familia::Encryption.derivation_count.value]
#=> [5, 5]

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
  retrieved = model.test_field  # ConcealedString (no decrypt)
  [val, retrieved.to_s]
end
# With secure-by-default, retrieved values are always '[CONCEALED]'
all_match = operation_pairs.all? { |pair| pair[1] == '[CONCEALED]' }
[all_match, Familia::Encryption.derivation_count.value]
#=> [true, 3]

## Empty string handling doesn't trigger derivation
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-empty')
model.test_field = ''
empty_result = model.test_field
# Empty string treated as nil, returns nil
[empty_result, Familia::Encryption.derivation_count.value]
#=> [nil, 0]

## Nil values don't trigger derivation
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-nil')
model.test_field = nil
nil_result = model.test_field
[nil_result, Familia::Encryption.derivation_count.value]
#=> [nil, 0]

## Key version rotation increments derivation count
Familia::Encryption.reset_derivation_count!
model = FreshKeyDerivationTest.new(user_id: 'test-rotation')
model.test_field = 'original'  # v1 encrypt
Familia.config.current_key_version = :v2
model.test_field = 'updated'   # v2 encrypt
retrieved = model.test_field   # ConcealedString (no decrypt)
# With secure-by-default, only encryptions trigger derivation
Familia::Encryption.derivation_count.value
#=> 2

Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
