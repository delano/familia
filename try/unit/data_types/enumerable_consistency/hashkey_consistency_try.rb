# try/unit/data_types/enumerable_consistency/hashkey_consistency_try.rb
#
# frozen_string_literal: true

# Tests that cursor-based `each` produces identical results to legacy `hgetall`.
# HashKey uses HSCAN for memory-efficient iteration.

require_relative '../../../support/helpers/test_helpers'

# Setup: Create test hash with varied data (50+ items for pagination testing)
@bone = Bone.new 'hashkey_consistency_test'

# Populate with varied field/value pairs
(1..60).each do |i|
  @bone.props["field_#{i.to_s.rjust(3, '0')}"] = "value_#{i}"
end

# Add some varied patterns for matching tests
@bone.props['config_timeout'] = 30
@bone.props['config_retries'] = 3
@bone.props['setting_enabled'] = true
@bone.props['setting_name'] = 'test'

# ============================================================
# each.to_h vs hgetall consistency
# ============================================================

## HashKey#each.to_h matches hgetall
each_hash = @bone.props.each.to_h
hgetall_hash = @bone.props.hgetall
each_hash == hgetall_hash
#=> true

## HashKey#each.to_h has same size as hgetall
@bone.props.each.to_h.size == @bone.props.hgetall.size
#=> true

## HashKey#each.to_h size matches field_count
@bone.props.each.to_h.size == @bone.props.field_count
#=> true

## HashKey#each yields same keys as hgetall.keys
each_keys = @bone.props.each.map { |k, _v| k }.sort
hgetall_keys = @bone.props.hgetall.keys.sort
each_keys == hgetall_keys
#=> true

## HashKey#each yields same values as hgetall.values
each_values = @bone.props.each.map { |_k, v| v }.sort_by(&:to_s)
hgetall_values = @bone.props.hgetall.values.sort_by(&:to_s)
each_values == hgetall_values
#=> true

# ============================================================
# Batch size variations
# ============================================================

## HashKey#each with batch_size=1 matches hgetall
each_hash = @bone.props.each(batch_size: 1).to_h
hgetall_hash = @bone.props.hgetall
each_hash == hgetall_hash
#=> true

## HashKey#each with batch_size=5 matches hgetall
each_hash = @bone.props.each(batch_size: 5).to_h
hgetall_hash = @bone.props.hgetall
each_hash == hgetall_hash
#=> true

## HashKey#each with batch_size=10 matches hgetall
each_hash = @bone.props.each(batch_size: 10).to_h
hgetall_hash = @bone.props.hgetall
each_hash == hgetall_hash
#=> true

## HashKey#each with batch_size=50 matches hgetall
each_hash = @bone.props.each(batch_size: 50).to_h
hgetall_hash = @bone.props.hgetall
each_hash == hgetall_hash
#=> true

## HashKey#each with batch_size=1000 (larger than hash) matches hgetall
each_hash = @bone.props.each(batch_size: 1000).to_h
hgetall_hash = @bone.props.hgetall
each_hash == hgetall_hash
#=> true

# ============================================================
# Filtered each(matching:) consistency
# NOTE: matching: operates on field names (plain strings), not values
# ============================================================

## HashKey#each(matching:) with config_ pattern
each_hash = @bone.props.each(matching: 'config_*').to_h
expected = @bone.props.hgetall.select { |k, _v| k.start_with?('config_') }
each_hash == expected
#=> true

## HashKey#each(matching:) with setting_ pattern
each_hash = @bone.props.each(matching: 'setting_*').to_h
expected = @bone.props.hgetall.select { |k, _v| k.start_with?('setting_') }
each_hash == expected
#=> true

## HashKey#each(matching:) with field_ pattern
each_hash = @bone.props.each(matching: 'field_*').to_h
expected = @bone.props.hgetall.select { |k, _v| k.start_with?('field_') }
each_hash == expected
#=> true

## HashKey#each(matching:) wildcard returns all fields
each_hash = @bone.props.each(matching: '*').to_h
hgetall_hash = @bone.props.hgetall
each_hash == hgetall_hash
#=> true

## HashKey#each(matching:) count matches filtered hgetall count
each_count = @bone.props.each(matching: 'config_*').to_h.size
expected_count = @bone.props.hgetall.keys.count { |k| k.start_with?('config_') }
each_count == expected_count
#=> true

# ============================================================
# No data loss or duplication
# ============================================================

## HashKey#each has no duplicate keys
each_keys = @bone.props.each.map { |k, _v| k }
each_keys.size == each_keys.uniq.size
#=> true

## HashKey#hgetall has no duplicate keys
hgetall_keys = @bone.props.hgetall.keys
hgetall_keys.size == hgetall_keys.uniq.size
#=> true

## HashKey total count is consistent across methods
count_via_each = @bone.props.each.to_h.size
count_via_hgetall = @bone.props.hgetall.size
count_via_method = @bone.props.field_count
count_via_each == count_via_hgetall && count_via_hgetall == count_via_method
#=> true

# ============================================================
# Value type preservation
# ============================================================

## HashKey#each preserves integer values
each_hash = @bone.props.each.to_h
each_hash['config_timeout'] == 30
#=> true

## HashKey#each preserves boolean values
each_hash = @bone.props.each.to_h
each_hash['setting_enabled'] == true
#=> true

## HashKey#each preserves string values
each_hash = @bone.props.each.to_h
each_hash['setting_name'] == 'test'
#=> true

## HashKey#each values match hgetall values for special types
each_hash = @bone.props.each.to_h
hgetall_hash = @bone.props.hgetall
each_hash['config_timeout'] == hgetall_hash['config_timeout']
#=> true

# ============================================================
# Edge cases
# ============================================================

## Empty HashKey: each.to_h matches hgetall
@empty_bone = Bone.new 'hashkey_consistency_empty_test'
each_hash = @empty_bone.props.each.to_h
hgetall_hash = @empty_bone.props.hgetall
each_hash == hgetall_hash && each_hash == {}
#=> true

## Single field HashKey: each.to_h matches hgetall
@single_bone = Bone.new 'hashkey_consistency_single_test'
@single_bone.props['only_field'] = 'only_value'
each_hash = @single_bone.props.each.to_h
hgetall_hash = @single_bone.props.hgetall
each_hash == hgetall_hash
#=> true

## HashKey with special characters in field names
@special_bone = Bone.new 'hashkey_consistency_special_test'
@special_bone.props['field with spaces'] = 'value1'
@special_bone.props['field:with:colons'] = 'value2'
@special_bone.props['field/with/slashes'] = 'value3'
each_hash = @special_bone.props.each.to_h
hgetall_hash = @special_bone.props.hgetall
each_hash == hgetall_hash
#=> true

# ============================================================
# Batch size does not affect filtered results
# ============================================================

## HashKey#each with matching and batch_size=1 matches expected
each_hash = @bone.props.each(matching: 'config_*', batch_size: 1).to_h
expected = @bone.props.hgetall.select { |k, _v| k.start_with?('config_') }
each_hash == expected
#=> true

## HashKey#each with matching and batch_size=10 matches expected
each_hash = @bone.props.each(matching: 'config_*', batch_size: 10).to_h
expected = @bone.props.hgetall.select { |k, _v| k.start_with?('config_') }
each_hash == expected
#=> true

## HashKey#each with matching and batch_size=100 matches expected
each_hash = @bone.props.each(matching: 'config_*', batch_size: 100).to_h
expected = @bone.props.hgetall.select { |k, _v| k.start_with?('config_') }
each_hash == expected
#=> true

# Teardown: Clean up test data
@bone.props.delete!
@empty_bone.props.delete! if defined?(@empty_bone) && @empty_bone
@single_bone.props.delete! if defined?(@single_bone) && @single_bone
@special_bone.props.delete! if defined?(@special_bone) && @special_bone
