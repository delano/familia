# try/unit/data_types/enumerable_consistency/sorted_set_consistency_try.rb
#
# frozen_string_literal: true

# Tests that cursor-based `each` produces identical results to legacy `membersraw`/`collectraw`.
# SortedSet uses ZSCAN for unbounded iteration and ZRANGEBYSCORE for bounded queries.

require_relative '../../../support/helpers/test_helpers'

# Setup: Create test sorted set with varied data (50+ items for pagination testing)
@bone = Bone.new 'sorted_set_consistency_test'

# Populate with varied scores for testing
(1..60).each do |i|
  @bone.metrics.add "item_#{i.to_s.rjust(3, '0')}", i * 10.0
end

# Add some edge case values
@bone.metrics.add 'special_negative', -100.0
@bone.metrics.add 'special_zero', 0.0
@bone.metrics.add 'special_float', 123.456
@bone.metrics.add 'special_large', 999999.0

# ============================================================
# each.to_a vs membersraw consistency
# ============================================================

## SortedSet#each.to_a matches membersraw after deserialization (sorted comparison)
new_result = @bone.metrics.each.to_a.sort
raw_result = @bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## SortedSet#each.to_a has same count as membersraw
@bone.metrics.each.to_a.size == @bone.metrics.membersraw.size
#=> true

## SortedSet#each.to_a count matches element_count
@bone.metrics.each.to_a.size == @bone.metrics.element_count
#=> true

## SortedSet#each.to_a includes all raw members
raw_members = @bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }
each_members = @bone.metrics.each.to_a
(raw_members - each_members).empty?
#=> true

## SortedSet#each.to_a has no extra members beyond raw
each_members = @bone.metrics.each.to_a
raw_members = @bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }
(each_members - raw_members).empty?
#=> true

# ============================================================
# map consistency with collectraw
# ============================================================

## SortedSet#map matches collectraw with identity transform (sorted)
new_result = @bone.metrics.map { |x| x }.sort
raw_result = @bone.metrics.collectraw { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## SortedSet#map with upcase matches collectraw transformation
new_result = @bone.metrics.map { |x| x.upcase }.sort
raw_result = @bone.metrics.collectraw { |v| Familia::JsonSerializer.parse(v).upcase }.sort
new_result == raw_result
#=> true

## SortedSet#select matches selectraw filtering
new_result = @bone.metrics.select { |x| x.start_with?('item_') }.sort
raw_result = @bone.metrics.selectraw { |v| Familia::JsonSerializer.parse(v).start_with?('item_') }.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

# ============================================================
# Batch size variations
# ============================================================

## SortedSet#each with batch_size=1 matches membersraw
new_result = @bone.metrics.each(batch_size: 1).to_a.sort
raw_result = @bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## SortedSet#each with batch_size=5 matches membersraw
new_result = @bone.metrics.each(batch_size: 5).to_a.sort
raw_result = @bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## SortedSet#each with batch_size=10 matches membersraw
new_result = @bone.metrics.each(batch_size: 10).to_a.sort
raw_result = @bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## SortedSet#each with batch_size=50 matches membersraw
new_result = @bone.metrics.each(batch_size: 50).to_a.sort
raw_result = @bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## SortedSet#each with batch_size=1000 (larger than set) matches membersraw
new_result = @bone.metrics.each(batch_size: 1000).to_a.sort
raw_result = @bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

# ============================================================
# Filtered each(since:, until:) vs manual filtering
# ============================================================

## SortedSet#each(since:) matches manual filtering of membersraw
since_score = 300.0
new_result = @bone.metrics.each(since: since_score).to_a.sort
raw_result = @bone.metrics.rangebyscore(since_score, '+inf').sort
new_result == raw_result
#=> true

## SortedSet#each(until:) matches manual filtering of membersraw
until_score = 200.0
new_result = @bone.metrics.each(until: until_score).to_a.sort
raw_result = @bone.metrics.rangebyscore('-inf', until_score).sort
new_result == raw_result
#=> true

## SortedSet#each(since:, until:) matches rangebyscore
since_score = 100.0
until_score = 400.0
new_result = @bone.metrics.each(since: since_score, until: until_score).to_a.sort
raw_result = @bone.metrics.rangebyscore(since_score, until_score).sort
new_result == raw_result
#=> true

## SortedSet#each with Time conversion matches rangebyscore
# Time.at(300) converts to score 300.0
since_time = Time.at(300)
until_time = Time.at(500)
new_result = @bone.metrics.each(since: since_time, until: until_time).to_a.sort
raw_result = @bone.metrics.rangebyscore(300.0, 500.0).sort
new_result == raw_result
#=> true

# ============================================================
# No data loss or duplication
# ============================================================

## SortedSet#each has no duplicates
each_result = @bone.metrics.each.to_a
each_result.size == each_result.uniq.size
#=> true

## SortedSet#membersraw has no duplicates
raw_result = @bone.metrics.membersraw
raw_result.size == raw_result.uniq.size
#=> true

## SortedSet total count is consistent across methods
count_via_each = @bone.metrics.each.to_a.size
count_via_raw = @bone.metrics.membersraw.size
count_via_method = @bone.metrics.element_count
count_via_each == count_via_raw && count_via_raw == count_via_method
#=> true

# ============================================================
# Edge cases
# ============================================================

## Empty SortedSet: each.to_a matches membersraw
@empty_bone = Bone.new 'sorted_set_consistency_empty_test'
new_result = @empty_bone.metrics.each.to_a
raw_result = @empty_bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }
new_result == raw_result && new_result == []
#=> true

## Single element SortedSet: each.to_a matches membersraw
@single_bone = Bone.new 'sorted_set_consistency_single_test'
@single_bone.metrics.add 'only_item', 42.0
new_result = @single_bone.metrics.each.to_a
raw_result = @single_bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }
new_result == raw_result
#=> true

## SortedSet with special characters: each.to_a matches membersraw
@special_bone = Bone.new 'sorted_set_consistency_special_test'
@special_bone.metrics.add 'item with spaces', 1.0
@special_bone.metrics.add 'item:with:colons', 2.0
@special_bone.metrics.add 'item/with/slashes', 3.0
new_result = @special_bone.metrics.each.to_a.sort
raw_result = @special_bone.metrics.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

# Teardown: Clean up test data
@bone.metrics.delete!
@empty_bone.metrics.delete! if defined?(@empty_bone) && @empty_bone
@single_bone.metrics.delete! if defined?(@single_bone) && @single_bone
@special_bone.metrics.delete! if defined?(@special_bone) && @special_bone
