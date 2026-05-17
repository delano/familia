# try/unit/data_types/enumerable_consistency/listkey_consistency_try.rb
#
# frozen_string_literal: true

# Tests that cursor-based `each` produces identical results to legacy `membersraw`/`collectraw`.
# ListKey uses LRANGE pagination for iteration (Redis lists do not support SCAN).
# Unlike sets, lists preserve order, so order must match exactly.

require_relative '../../../support/helpers/test_helpers'

# Setup: Create test list with varied data (50+ items for pagination testing)
@bone = Bone.new 'listkey_consistency_test'

# Populate with ordered data
(1..60).each do |i|
  @bone.owners.push "owner_#{i.to_s.rjust(3, '0')}"
end

# Add some additional items
@bone.owners.push 'admin_primary'
@bone.owners.push 'admin_secondary'
@bone.owners.push 'guest_readonly'

# ============================================================
# each.to_a vs membersraw consistency (order matters for lists)
# ============================================================

## ListKey#each.to_a matches members (exact order)
new_result = @bone.owners.each.to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

## ListKey#each.to_a has same count as members
@bone.owners.each.to_a.size == @bone.owners.members.size
#=> true

## ListKey#each.to_a count matches element_count
@bone.owners.each.to_a.size == @bone.owners.element_count
#=> true

## ListKey#each.to_a first element matches members first
new_first = @bone.owners.each.to_a.first
members_first = @bone.owners.members.first
new_first == members_first
#=> true

## ListKey#each.to_a last element matches members last
new_last = @bone.owners.each.to_a.last
members_last = @bone.owners.members.last
new_last == members_last
#=> true

# ============================================================
# map consistency with collectraw
# ============================================================

## ListKey#map matches members with identity transform (exact order)
new_result = @bone.owners.map { |x| x }
members_result = @bone.owners.members
new_result == members_result
#=> true

## ListKey#map with upcase matches members transformation
new_result = @bone.owners.map { |x| x.upcase }
members_result = @bone.owners.members.map(&:upcase)
new_result == members_result
#=> true

## ListKey#select matches members filtering (preserves order)
new_result = @bone.owners.select { |x| x.start_with?('owner_') }
members_result = @bone.owners.members.select { |m| m.start_with?('owner_') }
new_result == members_result
#=> true

# ============================================================
# Batch size variations (must not affect order)
# ============================================================

## ListKey#each with batch_size=1 matches members (exact order)
new_result = @bone.owners.each(batch_size: 1).to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

## ListKey#each with batch_size=5 matches members (exact order)
new_result = @bone.owners.each(batch_size: 5).to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

## ListKey#each with batch_size=10 matches members (exact order)
new_result = @bone.owners.each(batch_size: 10).to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

## ListKey#each with batch_size=50 matches members (exact order)
new_result = @bone.owners.each(batch_size: 50).to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

## ListKey#each with batch_size=1000 (larger than list) matches members
new_result = @bone.owners.each(batch_size: 1000).to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

# ============================================================
# Pagination boundary testing
# ============================================================

## ListKey#each with batch_size exactly matching list size
list_size = @bone.owners.element_count
new_result = @bone.owners.each(batch_size: list_size).to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

## ListKey#each with batch_size one less than list size
list_size = @bone.owners.element_count
new_result = @bone.owners.each(batch_size: list_size - 1).to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

## ListKey#each with batch_size one more than list size
list_size = @bone.owners.element_count
new_result = @bone.owners.each(batch_size: list_size + 1).to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

## ListKey#each with prime batch_size (37) tests non-aligned pagination
new_result = @bone.owners.each(batch_size: 37).to_a
members_result = @bone.owners.members
new_result == members_result
#=> true

# ============================================================
# No data loss or duplication
# ============================================================

## ListKey#each produces same length as members
@bone.owners.each.to_a.size == @bone.owners.members.size
#=> true

## ListKey total count is consistent across methods
count_via_each = @bone.owners.each.to_a.size
count_via_members = @bone.owners.members.size
count_via_method = @bone.owners.element_count
count_via_each == count_via_members && count_via_members == count_via_method
#=> true

## ListKey#each index consistency (each element at correct position)
each_result = @bone.owners.each.to_a
members_result = @bone.owners.members
each_result.each_with_index.all? { |elem, idx| elem == members_result[idx] }
#=> true

# ============================================================
# Edge cases
# ============================================================

## Empty ListKey: each.to_a matches members
@empty_bone = Bone.new 'listkey_consistency_empty_test'
new_result = @empty_bone.owners.each.to_a
members_result = @empty_bone.owners.members
new_result == members_result && new_result == []
#=> true

## Single element ListKey: each.to_a matches members
@single_bone = Bone.new 'listkey_consistency_single_test'
@single_bone.owners.push 'only_owner'
new_result = @single_bone.owners.each.to_a
members_result = @single_bone.owners.members
new_result == members_result
#=> true

## ListKey with special characters: each.to_a matches members
@special_bone = Bone.new 'listkey_consistency_special_test'
@special_bone.owners.push 'owner with spaces'
@special_bone.owners.push 'owner:with:colons'
@special_bone.owners.push 'owner/with/slashes'
new_result = @special_bone.owners.each.to_a
members_result = @special_bone.owners.members
new_result == members_result
#=> true

## ListKey with duplicate values: each.to_a matches members (lists allow duplicates)
@dup_bone = Bone.new 'listkey_consistency_dup_test'
@dup_bone.owners.push 'duplicate_item'
@dup_bone.owners.push 'unique_item'
@dup_bone.owners.push 'duplicate_item'
@dup_bone.owners.push 'duplicate_item'
new_result = @dup_bone.owners.each.to_a
members_result = @dup_bone.owners.members
new_result == members_result
#=> true

## ListKey duplicate count preserved
@dup_bone.owners.each.to_a.count('duplicate_item') == 3
#=> true

# ============================================================
# Large list pagination stress test
# ============================================================

## Large ListKey: each with small batch_size matches members
@large_bone = Bone.new 'listkey_consistency_large_test'
(1..150).each { |i| @large_bone.owners.push "large_owner_#{i}" }
new_result = @large_bone.owners.each(batch_size: 7).to_a
members_result = @large_bone.owners.members
new_result == members_result
#=> true

## Large ListKey: count matches across methods
count_via_each = @large_bone.owners.each.to_a.size
count_via_members = @large_bone.owners.members.size
count_via_each == count_via_members && count_via_each == 150
#=> true

# Teardown: Clean up test data
@bone.owners.delete!
@empty_bone.owners.delete! if defined?(@empty_bone) && @empty_bone
@single_bone.owners.delete! if defined?(@single_bone) && @single_bone
@special_bone.owners.delete! if defined?(@special_bone) && @special_bone
@dup_bone.owners.delete! if defined?(@dup_bone) && @dup_bone
@large_bone.owners.delete! if defined?(@large_bone) && @large_bone
