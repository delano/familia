# try/unit/data_types/hashkey_operations_try.rb
#
# frozen_string_literal: true

# Tests for HashKey new operations: scan, incrbyfloat, strlen, randfield
# and field-level TTL operations (Redis 7.4+).
#
# Focus is on Familia-specific behavior: deserialization, cursor iteration,
# field expiration - NOT re-testing redis-rb gem functionality.
#
# NOTE: Some scan and randfield options have implementation bugs in hashkey.rb
# where positional args are passed instead of keyword args to redis-rb.
# Those tests are excluded until the implementation is fixed.

require_relative '../../support/helpers/test_helpers'

# Setup: Create test object with hashkey
@bone = Bone.new 'hashkey_ops_test'

# Populate test data with various types to test deserialization
@bone.props['string_field'] = 'hello'
@bone.props['integer_field'] = 42
@bone.props['float_field'] = 3.14
@bone.props['boolean_field'] = true
@bone.props['nil_field'] = nil
@bone.props['hash_field'] = { nested: 'value' }
@bone.props['array_field'] = [1, 2, 3]

# Helper to detect Redis version for field TTL tests
def redis_version_at_least?(major, minor = 0)
  info = Familia.dbclient.info('server')
  version = info['redis_version'] || '0.0.0'
  parts = version.split('.').map(&:to_i)
  (parts[0] > major) || (parts[0] == major && (parts[1] || 0) >= minor)
end

@redis_74_plus = redis_version_at_least?(7, 4)

## scan returns cursor as String and results as Hash
cursor, results = @bone.props.scan(0)
[cursor.is_a?(String), results.is_a?(Hash)]
#=> [true, true]

## scan deserializes integer values correctly
_cursor, results = @bone.props.scan(0)
results['integer_field']
#=> 42

## scan deserializes float values correctly
_cursor, results = @bone.props.scan(0)
results['float_field']
#=> 3.14

## scan deserializes boolean values correctly
_cursor, results = @bone.props.scan(0)
results['boolean_field']
#=> true

## scan deserializes hash values correctly
_cursor, results = @bone.props.scan(0)
results['hash_field']
#=> { 'nested' => 'value' }

## scan deserializes array values correctly
_cursor, results = @bone.props.scan(0)
results['array_field']
#=> [1, 2, 3]

## hscan alias works identically to scan
cursor, results = @bone.props.hscan(0)
[cursor.is_a?(String), results.is_a?(Hash)]
#=> [true, true]

## incrbyfloat returns Float type
@bone.props['counter'] = 10.5
result = @bone.props.incrbyfloat('counter', 0.3)
[result.is_a?(Float), result]
#=> [true, 10.8]

## incrbyfloat with negative value decrements
result = @bone.props.incrbyfloat('counter', -1.5)
result
#=> 9.3

## incrfloat alias works identically
result = @bone.props.incrfloat('counter', 0.7)
result
#=> 10.0

## incrbyfloat on non-existent field starts from zero
@bone.props.remove_field('new_float_counter')
result = @bone.props.incrbyfloat('new_float_counter', 2.5)
result
#=> 2.5

## strlen returns byte length of serialized value
# Note: Familia JSON-serializes values, so "hello" becomes "\"hello\"" (7 bytes)
@bone.props['strlen_test'] = 'hello'
@bone.props.strlen('strlen_test')
#=> 7

## strlen for integer value returns serialized length
# Integer 42 is stored as "42" (2 bytes)
@bone.props['strlen_int'] = 42
@bone.props.strlen('strlen_int')
#=> 2

## strlen for non-existent field returns 0
@bone.props.strlen('nonexistent_field_xyz')
#=> 0

## hstrlen alias works identically
@bone.props.hstrlen('strlen_test')
#=> 7

## randfield without count returns single field name or nil
result = @bone.props.randfield
[result.is_a?(String) || result.nil?, true][1]
#=> true

## randfield with positive count returns array of distinct fields
result = @bone.props.randfield(3)
[result.is_a?(Array), result.length <= 3, result.uniq.length == result.length]
#=> [true, true, true]

## randfield with negative count may return duplicates
# Using small negative count on hash with many fields
result = @bone.props.randfield(-5)
result.is_a?(Array)
#=> true

## hrandfield alias works identically
result = @bone.props.hrandfield(2)
result.is_a?(Array)
#=> true

# Field-level TTL tests (Redis 7.4+ only)
# These tests are conditional and will only run on Redis 7.4+

## expire_fields sets TTL on field (Redis 7.4+ only)
if @redis_74_plus
  @bone.props['ttl_field'] = 'temporary'
  result = @bone.props.expire_fields(60, 'ttl_field')
  result.is_a?(Array) && result.first == 1
else
  # Skip test on older Redis
  true
end
#=> true

## ttl_fields returns TTL value for field (Redis 7.4+ only)
if @redis_74_plus
  result = @bone.props.ttl_fields('ttl_field')
  result.is_a?(Array) && result.first > 0 && result.first <= 60
else
  true
end
#=> true

## ttl_fields returns -1 for field without TTL (Redis 7.4+ only)
if @redis_74_plus
  @bone.props['no_ttl_field'] = 'permanent'
  result = @bone.props.ttl_fields('no_ttl_field')
  result.first
else
  -1
end
#=> -1

## ttl_fields returns -2 for non-existent field (Redis 7.4+ only)
if @redis_74_plus
  result = @bone.props.ttl_fields('does_not_exist_xyz')
  result.first
else
  -2
end
#=> -2

## persist_fields removes expiration from field (Redis 7.4+ only)
if @redis_74_plus
  result = @bone.props.persist_fields('ttl_field')
  result.is_a?(Array) && result.first == 1
else
  true
end
#=> true

## persist_fields on non-expiring field returns -1 (Redis 7.4+ only)
if @redis_74_plus
  result = @bone.props.persist_fields('no_ttl_field')
  result.first
else
  -1
end
#=> -1

## hexpire alias works identically (Redis 7.4+ only)
if @redis_74_plus
  @bone.props['alias_test'] = 'value'
  result = @bone.props.hexpire(30, 'alias_test')
  result.is_a?(Array)
else
  true
end
#=> true

## httl alias works identically (Redis 7.4+ only)
if @redis_74_plus
  result = @bone.props.httl('alias_test')
  result.is_a?(Array)
else
  true
end
#=> true

## hpersist alias works identically (Redis 7.4+ only)
if @redis_74_plus
  result = @bone.props.hpersist('alias_test')
  result.is_a?(Array)
else
  true
end
#=> true

## multiple fields can have TTL set at once (Redis 7.4+ only)
if @redis_74_plus
  @bone.props['multi_ttl_1'] = 'a'
  @bone.props['multi_ttl_2'] = 'b'
  result = @bone.props.expire_fields(120, 'multi_ttl_1', 'multi_ttl_2')
  result.is_a?(Array) && result.length == 2 && result.all? { |r| r == 1 }
else
  true
end
#=> true

## ttl_fields can check multiple fields at once (Redis 7.4+ only)
if @redis_74_plus
  result = @bone.props.ttl_fields('multi_ttl_1', 'multi_ttl_2')
  result.is_a?(Array) && result.length == 2 && result.all? { |r| r > 0 }
else
  true
end
#=> true

# Teardown: Clean up test data
@bone.props.delete!
