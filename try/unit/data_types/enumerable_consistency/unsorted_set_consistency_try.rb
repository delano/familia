# try/unit/data_types/enumerable_consistency/unsorted_set_consistency_try.rb
#
# frozen_string_literal: true

# Tests that cursor-based `each` produces identical results to legacy `membersraw`/`collectraw`.
# UnsortedSet uses SSCAN for memory-efficient iteration.

require_relative '../../../support/helpers/test_helpers'

# Setup: Create test unsorted set with varied data (50+ items for pagination testing)
@bone = Bone.new 'unsorted_set_consistency_test'

# Populate with varied data
(1..60).each do |i|
  @bone.tags.add "tag_#{i.to_s.rjust(3, '0')}"
end

# Add some varied patterns for matching tests
@bone.tags.add 'feature_auth'
@bone.tags.add 'feature_billing'
@bone.tags.add 'bug_critical'
@bone.tags.add 'bug_minor'

# ============================================================
# each.to_a vs membersraw consistency
# ============================================================

## UnsortedSet#each.to_a matches membersraw after deserialization (sorted comparison)
new_result = @bone.tags.each.to_a.sort
raw_result = @bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## UnsortedSet#each.to_a has same count as membersraw
@bone.tags.each.to_a.size == @bone.tags.membersraw.size
#=> true

## UnsortedSet#each.to_a count matches element_count
@bone.tags.each.to_a.size == @bone.tags.element_count
#=> true

## UnsortedSet#each.to_a includes all raw members
raw_members = @bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }
each_members = @bone.tags.each.to_a
(raw_members - each_members).empty?
#=> true

## UnsortedSet#each.to_a has no extra members beyond raw
each_members = @bone.tags.each.to_a
raw_members = @bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }
(each_members - raw_members).empty?
#=> true

# ============================================================
# map consistency with collectraw
# ============================================================

## UnsortedSet#map matches collectraw with identity transform (sorted)
new_result = @bone.tags.map { |x| x }.sort
raw_result = @bone.tags.collectraw { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## UnsortedSet#map with upcase matches collectraw transformation
new_result = @bone.tags.map { |x| x.upcase }.sort
raw_result = @bone.tags.collectraw { |v| Familia::JsonSerializer.parse(v).upcase }.sort
new_result == raw_result
#=> true

## UnsortedSet#select matches selectraw filtering
new_result = @bone.tags.select { |x| x.start_with?('tag_') }.sort
raw_result = @bone.tags.selectraw { |v| Familia::JsonSerializer.parse(v).start_with?('tag_') }.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

# ============================================================
# Batch size variations
# ============================================================

## UnsortedSet#each with batch_size=1 matches membersraw
new_result = @bone.tags.each(batch_size: 1).to_a.sort
raw_result = @bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## UnsortedSet#each with batch_size=5 matches membersraw
new_result = @bone.tags.each(batch_size: 5).to_a.sort
raw_result = @bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## UnsortedSet#each with batch_size=10 matches membersraw
new_result = @bone.tags.each(batch_size: 10).to_a.sort
raw_result = @bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## UnsortedSet#each with batch_size=50 matches membersraw
new_result = @bone.tags.each(batch_size: 50).to_a.sort
raw_result = @bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

## UnsortedSet#each with batch_size=1000 (larger than set) matches membersraw
new_result = @bone.tags.each(batch_size: 1000).to_a.sort
raw_result = @bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

# ============================================================
# Filtered each(matching:) consistency
# NOTE: matching: operates on raw storage (JSON-encoded), so we compare
# against full set filtered post-deserialization
# ============================================================

## UnsortedSet#each(matching:) with feature substring
new_result = @bone.tags.each(matching: '*feature*').to_a.sort
expected = @bone.tags.members.select { |m| m.include?('feature') }.sort
new_result == expected
#=> true

## UnsortedSet#each(matching:) with bug substring
new_result = @bone.tags.each(matching: '*bug*').to_a.sort
expected = @bone.tags.members.select { |m| m.include?('bug') }.sort
new_result == expected
#=> true

## UnsortedSet#each(matching:) with tag_ pattern
new_result = @bone.tags.each(matching: '*tag_*').to_a.sort
expected = @bone.tags.members.select { |m| m.include?('tag_') }.sort
new_result == expected
#=> true

## UnsortedSet#each(matching:) wildcard returns all members
new_result = @bone.tags.each(matching: '*').to_a.sort
raw_result = @bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

# ============================================================
# No data loss or duplication
# ============================================================

## UnsortedSet#each has no duplicates
each_result = @bone.tags.each.to_a
each_result.size == each_result.uniq.size
#=> true

## UnsortedSet#membersraw has no duplicates
raw_result = @bone.tags.membersraw
raw_result.size == raw_result.uniq.size
#=> true

## UnsortedSet total count is consistent across methods
count_via_each = @bone.tags.each.to_a.size
count_via_raw = @bone.tags.membersraw.size
count_via_method = @bone.tags.element_count
count_via_each == count_via_raw && count_via_raw == count_via_method
#=> true

# ============================================================
# Edge cases
# ============================================================

## Empty UnsortedSet: each.to_a matches membersraw
@empty_bone = Bone.new 'unsorted_set_consistency_empty_test'
new_result = @empty_bone.tags.each.to_a
raw_result = @empty_bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }
new_result == raw_result && new_result == []
#=> true

## Single element UnsortedSet: each.to_a matches membersraw
@single_bone = Bone.new 'unsorted_set_consistency_single_test'
@single_bone.tags.add 'only_item'
new_result = @single_bone.tags.each.to_a
raw_result = @single_bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }
new_result == raw_result
#=> true

## UnsortedSet with special characters: each.to_a matches membersraw
@special_bone = Bone.new 'unsorted_set_consistency_special_test'
@special_bone.tags.add 'item with spaces'
@special_bone.tags.add 'item:with:colons'
@special_bone.tags.add 'item/with/slashes'
new_result = @special_bone.tags.each.to_a.sort
raw_result = @special_bone.tags.membersraw.map { |v| Familia::JsonSerializer.parse(v) }.sort
new_result == raw_result
#=> true

# ============================================================
# Batch size does not affect filtered results
# ============================================================

## UnsortedSet#each with matching and batch_size=1 matches expected
new_result = @bone.tags.each(matching: '*feature*', batch_size: 1).to_a.sort
expected = @bone.tags.members.select { |m| m.include?('feature') }.sort
new_result == expected
#=> true

## UnsortedSet#each with matching and batch_size=10 matches expected
new_result = @bone.tags.each(matching: '*feature*', batch_size: 10).to_a.sort
expected = @bone.tags.members.select { |m| m.include?('feature') }.sort
new_result == expected
#=> true

## UnsortedSet#each with matching and batch_size=100 matches expected
new_result = @bone.tags.each(matching: '*feature*', batch_size: 100).to_a.sort
expected = @bone.tags.members.select { |m| m.include?('feature') }.sort
new_result == expected
#=> true

# Teardown: Clean up test data
@bone.tags.delete!
@empty_bone.tags.delete! if defined?(@empty_bone) && @empty_bone
@single_bone.tags.delete! if defined?(@single_bone) && @single_bone
@special_bone.tags.delete! if defined?(@special_bone) && @special_bone
