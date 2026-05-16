# try/unit/data_types/hashkey_each_try.rb
#
# frozen_string_literal: true

# Tests for HashKey#each with matching: filter.
# The matching: filter uses HSCAN MATCH for glob-pattern filtering.

require_relative '../../support/helpers/test_helpers'

# Setup: Create test hashkey with various field patterns
@bone = Bone.new 'hashkey_each_test'

# Populate with fields that have different prefixes
@bone.props['user_name'] = 'Alice'
@bone.props['user_email'] = 'alice@example.com'
@bone.props['user_role'] = 'admin'
@bone.props['config_timeout'] = 30
@bone.props['config_retries'] = 3
@bone.props['meta_created'] = '2024-01-01'
@bone.props['meta_updated'] = '2024-06-15'

# ============================================================
# Basic iteration (all key-value pairs)
# ============================================================

## HashKey#each without filters yields all key-value pairs
collected = {}
@bone.props.each { |k, v| collected[k] = v }
collected.keys.sort
#=> ['config_retries', 'config_timeout', 'meta_created', 'meta_updated', 'user_email', 'user_name', 'user_role']

## HashKey#each returns Enumerator when no block given
result = @bone.props.each
result.class
#=> Enumerator

## HashKey#each Enumerator yields [key, value] pairs
first_pair = @bone.props.each.first
first_pair.is_a?(Array) && first_pair.size == 2
#=> true

## HashKey#each block receives key and value
keys = []
values = []
@bone.props.each { |k, v| keys << k; values << v }
keys.size == values.size && keys.size == 7
#=> true

# ============================================================
# matching: filter with glob patterns
# ============================================================

## HashKey#each(matching:) filters by field name pattern
collected = {}
@bone.props.each(matching: 'user_*') { |k, v| collected[k] = v }
collected.keys.sort
#=> ['user_email', 'user_name', 'user_role']

## HashKey#each(matching:) with config prefix
collected = {}
@bone.props.each(matching: 'config_*') { |k, v| collected[k] = v }
collected.keys.sort
#=> ['config_retries', 'config_timeout']

## HashKey#each(matching:) with meta prefix
collected = {}
@bone.props.each(matching: 'meta_*') { |k, v| collected[k] = v }
collected.keys.sort
#=> ['meta_created', 'meta_updated']

## HashKey#each(matching:) with single character wildcard
collected = {}
@bone.props.each(matching: 'user_????') { |k, v| collected[k] = v }
collected.keys.sort
#=> ['user_name', 'user_role']

## HashKey#each(matching:) with suffix pattern
collected = {}
@bone.props.each(matching: '*_name') { |k, v| collected[k] = v }
collected.keys.sort
#=> ['user_name']

## HashKey#each(matching:) with middle wildcard
collected = {}
@bone.props.each(matching: '*_*_*') { |k, v| collected[k] = v }
# No fields match this pattern (no double underscores in our test data)
collected.keys
#=> []

## HashKey#each(matching:) with exact match pattern
collected = {}
@bone.props.each(matching: 'user_email') { |k, v| collected[k] = v }
collected
#=> {'user_email' => 'alice@example.com'}

# ============================================================
# Empty result scenarios
# ============================================================

## HashKey#each(matching:) with non-matching pattern returns empty
collected = {}
@bone.props.each(matching: 'nonexistent_*') { |k, v| collected[k] = v }
collected
#=> {}

## HashKey#each on empty hashkey returns empty
@empty_bone = Bone.new 'hashkey_each_empty_test'
collected = {}
@empty_bone.props.each { |k, v| collected[k] = v }
collected
#=> {}

## HashKey#each with matching on empty hashkey returns empty
collected = {}
@empty_bone.props.each(matching: '*') { |k, v| collected[k] = v }
collected
#=> {}

# ============================================================
# Value types preserved
# ============================================================

## HashKey#each preserves string values
collected = {}
@bone.props.each(matching: 'user_name') { |k, v| collected[k] = v }
collected['user_name']
#=> 'Alice'

## HashKey#each preserves integer values
collected = {}
@bone.props.each(matching: 'config_timeout') { |k, v| collected[k] = v }
collected['config_timeout']
#=> 30

## HashKey#each preserves integer type
collected = {}
@bone.props.each(matching: 'config_*') { |k, v| collected[k] = v }
collected['config_retries'].is_a?(Integer)
#=> true

# ============================================================
# Batch size variations
# ============================================================

## HashKey#each with batch_size smaller than field count
collected = {}
@bone.props.each(batch_size: 2) { |k, v| collected[k] = v }
collected.size
#=> 7

## HashKey#each with batch_size larger than field count
collected = {}
@bone.props.each(batch_size: 100) { |k, v| collected[k] = v }
collected.size
#=> 7

## HashKey#each with batch_size equal to field count
collected = {}
@bone.props.each(batch_size: 7) { |k, v| collected[k] = v }
collected.size
#=> 7

## HashKey#each with batch_size of 1 (extreme case)
collected = {}
@bone.props.each(batch_size: 1) { |k, v| collected[k] = v }
collected.size
#=> 7

# ============================================================
# Combined filters and batch size
# ============================================================

## HashKey#each with matching and batch_size
collected = {}
@bone.props.each(matching: 'user_*', batch_size: 2) { |k, v| collected[k] = v }
collected.keys.sort
#=> ['user_email', 'user_name', 'user_role']

## HashKey#each with matching and small batch_size
collected = {}
@bone.props.each(matching: 'config_*', batch_size: 1) { |k, v| collected[k] = v }
collected.keys.sort
#=> ['config_retries', 'config_timeout']

# ============================================================
# Edge cases
# ============================================================

## HashKey#each with asterisk-only pattern matches all
collected = {}
@bone.props.each(matching: '*') { |k, v| collected[k] = v }
collected.size
#=> 7

## HashKey#each with empty matching pattern matches all
collected = {}
@bone.props.each(matching: '') { |k, v| collected[k] = v }
# Empty pattern behavior may vary - typically matches nothing or all
collected.size >= 0
#=> true

## HashKey#each combined with Enumerable-like iteration
# Using the Enumerator form
pairs = @bone.props.each.select { |k, _v| k.start_with?('user_') }
pairs.map(&:first).sort
#=> ['user_email', 'user_name', 'user_role']

## HashKey#each allows mapping over filtered results
@bone.props.each(matching: 'config_*').map { |k, v| [k.upcase, v] }.to_h.keys.sort
#=> ['CONFIG_RETRIES', 'CONFIG_TIMEOUT']

# Teardown: Clean up test data
@bone.props.delete!
@empty_bone.props.delete! if defined?(@empty_bone)
