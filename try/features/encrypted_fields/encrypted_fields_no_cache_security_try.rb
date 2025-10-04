# try/features/encrypted_fields_no_cache_security_try.rb
#
# Security tests for the no-cache encryption strategy
# These tests verify that we maintain security properties by NOT caching derived keys

require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

## No persistent key cache exists
## Verify that we don't maintain a key cache at all
Fiber[:familia_key_cache]
#=> nil

## Each encryption gets fresh key derivation
class NoCacheTestModel1 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :sensitive_data
end

@model = NoCacheTestModel1.new(user_id: 'test1')
@model.sensitive_data = 'secret-value'
#=> 'secret-value'

## No cache should be created
Fiber[:familia_key_cache]
#=> nil

## Reading the value also doesn't create cache
@retrieved = @model.sensitive_data
@retrieved.reveal do |decrypted_value|
  decrypted_value
end
#=> 'secret-value'

## repaired test
Fiber[:familia_key_cache]
#=> nil

## Multiple fields don't share state
class NoCacheTestModel2 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :field_a
  encrypted_field :field_b
  encrypted_field :field_c
end

@model2 = NoCacheTestModel2.new(user_id: 'test2')
@model2.field_a = 'value-a'
@model2.field_b = 'value-b'
@model2.field_c = 'value-c'
#=> 'value-c'

## Still no cache after multiple operations
Fiber[:familia_key_cache]
#=> nil

## All values can be retrieved correctly
@model2.field_a.reveal do |decrypted_value|
  decrypted_value
end
#=> 'value-a'

## Field b retrieves correctly
@model2.field_b.reveal do |decrypted_value|
  decrypted_value
end
#=> 'value-b'

## Field c retrieves correctly
@model2.field_c.reveal do |decrypted_value|
  decrypted_value
end
#=> 'value-c'

## Still no cache
Fiber[:familia_key_cache]
#=> nil

## Master keys are wiped after each operation
## This test verifies that master keys don't persist in memory
## We can't directly test memory wiping, but we verify the behavior
class NoCacheTestModel3 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :secret
end

# Create multiple instances with different data
@users = (1..10).map do |i|
  user = NoCacheTestModel3.new(user_id: "user#{i}")
  user.secret = "secret-#{i}"
  user
end

# Verify all can decrypt correctly (proves fresh derivation each time)
@users.each_with_index do |user, i|
  decrypted = user.secret
  decrypted == "secret-#{i}"
end.all?
#=> true

## Still no cache after multiple operations
Fiber[:familia_key_cache]
#=> nil

## Thread isolation (no shared state between threads)
class NoCacheTestModel4 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :thread_secret
end

@results = []
@threads = []

5.times do |i|
  @threads << Thread.new do
    # Each thread creates its own model
    model = NoCacheTestModel4.new(user_id: "thread#{i}")
    model.thread_secret = "thread-secret-#{i}"

    # Verify no cache in this thread
    cache_state = Fiber[:familia_key_cache]

    # Store results
    @results << {
      thread_id: i,
      cache_is_nil: cache_state.nil?,
      value_correct: model.thread_secret.reveal do |decrypted_value|
        decrypted_value == "thread-secret-#{i}"
      end
    }
  end
end

@threads.each(&:join)
@threads.size
#=> 5

## All threads should report no cache
@results.all? { |r| r[:cache_is_nil] }
#=> true

## All threads should have correct values
@results.all? {|r| r[:value_correct] }
#=> true

## Performance: Key derivation happens every time
## This test demonstrates that we prioritize security over performance
class NoCacheTestModel5 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :perf_field
end

@model5 = NoCacheTestModel5.new(user_id: 'perf-test')
@model5.perf_field = 'initial-value'
#=> 'initial-value'

## Multiple reads all trigger fresh key derivation
@read_results = 100.times.map do
  value = @model5.perf_field.reveal do |decrypted_value|
    decrypted_value
  end
  value == 'initial-value'
end

@read_results.all?
#=> true

## Still no cache after 100 operations
Fiber[:familia_key_cache]
#=> nil

## Key rotation works without cache complications
Familia.config.current_key_version = :v2

class NoCacheTestModel6 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :rotated_field
end

# Encrypt with v2
@model6 = NoCacheTestModel6.new(user_id: 'rotation-test')
@model6.rotated_field = 'encrypted-with-v2'

# Still no cache with new key version
Fiber[:familia_key_cache]
#=> nil

## Value is correctly encrypted/decrypted with v2
@model6.rotated_field.reveal do |decrypted_value|
  decrypted_value
end
#=> 'encrypted-with-v2'

## Reset to v1 for other tests
Familia.config.current_key_version = :v1
#=> :v1

# Teardown
Fiber[:familia_key_cache] = nil
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
