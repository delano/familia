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

# Setup: Create test customers for each_record testing (reference SortedSet)
@test_prefix = "unsorted_set_consistency_#{Time.now.to_i}"
@test_customers = (1..5).map do |i|
  c = Customer.new
  c.custid = "#{@test_prefix}_customer_#{i}"
  c.email = "test#{i}@example.com"
  c.role = "user"
  c.save
  c
end

# ============================================================
# each.to_a vs members consistency
# ============================================================

## UnsortedSet#each.to_a matches members (sorted comparison)
new_result = @bone.tags.each.to_a.sort
members_result = @bone.tags.members.sort
new_result == members_result
#=> true

## UnsortedSet#each.to_a has same count as members
@bone.tags.each.to_a.size == @bone.tags.members.size
#=> true

## UnsortedSet#each.to_a count matches element_count
@bone.tags.each.to_a.size == @bone.tags.element_count
#=> true

## UnsortedSet#each.to_a includes all members
members_list = @bone.tags.members
each_members = @bone.tags.each.to_a
(members_list - each_members).empty?
#=> true

## UnsortedSet#each.to_a has no extra members beyond members
each_members = @bone.tags.each.to_a
members_list = @bone.tags.members
(each_members - members_list).empty?
#=> true

# ============================================================
# map consistency with collectraw
# ============================================================

## UnsortedSet#map matches members with identity transform (sorted)
new_result = @bone.tags.map { |x| x }.sort
members_result = @bone.tags.members.sort
new_result == members_result
#=> true

## UnsortedSet#map with upcase matches members transformation
new_result = @bone.tags.map { |x| x.upcase }.sort
members_result = @bone.tags.members.map(&:upcase).sort
new_result == members_result
#=> true

## UnsortedSet#select matches members filtering
new_result = @bone.tags.select { |x| x.start_with?('tag_') }.sort
members_result = @bone.tags.members.select { |m| m.start_with?('tag_') }.sort
new_result == members_result
#=> true

# ============================================================
# Batch size variations
# ============================================================

## UnsortedSet#each with batch_size=1 matches members
new_result = @bone.tags.each(batch_size: 1).to_a.sort
members_result = @bone.tags.members.sort
new_result == members_result
#=> true

## UnsortedSet#each with batch_size=5 matches members
new_result = @bone.tags.each(batch_size: 5).to_a.sort
members_result = @bone.tags.members.sort
new_result == members_result
#=> true

## UnsortedSet#each with batch_size=10 matches members
new_result = @bone.tags.each(batch_size: 10).to_a.sort
members_result = @bone.tags.members.sort
new_result == members_result
#=> true

## UnsortedSet#each with batch_size=50 matches members
new_result = @bone.tags.each(batch_size: 50).to_a.sort
members_result = @bone.tags.members.sort
new_result == members_result
#=> true

## UnsortedSet#each with batch_size=1000 (larger than set) matches members
new_result = @bone.tags.each(batch_size: 1000).to_a.sort
members_result = @bone.tags.members.sort
new_result == members_result
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
members_result = @bone.tags.members.sort
new_result == members_result
#=> true

# ============================================================
# No data loss or duplication
# ============================================================

## UnsortedSet#each has no duplicates
each_result = @bone.tags.each.to_a
each_result.size == each_result.uniq.size
#=> true

## UnsortedSet#members has no duplicates
members_result = @bone.tags.members
members_result.size == members_result.uniq.size
#=> true

## UnsortedSet total count is consistent across methods
count_via_each = @bone.tags.each.to_a.size
count_via_members = @bone.tags.members.size
count_via_method = @bone.tags.element_count
count_via_each == count_via_members && count_via_members == count_via_method
#=> true

# ============================================================
# Edge cases
# ============================================================

## Empty UnsortedSet: each.to_a matches members
@empty_bone = Bone.new 'unsorted_set_consistency_empty_test'
new_result = @empty_bone.tags.each.to_a
members_result = @empty_bone.tags.members
new_result == members_result && new_result == []
#=> true

## Single element UnsortedSet: each.to_a matches members
@single_bone = Bone.new 'unsorted_set_consistency_single_test'
@single_bone.tags.add 'only_item'
new_result = @single_bone.tags.each.to_a
members_result = @single_bone.tags.members
new_result == members_result
#=> true

## UnsortedSet with special characters: each.to_a matches members
@special_bone = Bone.new 'unsorted_set_consistency_special_test'
@special_bone.tags.add 'item with spaces'
@special_bone.tags.add 'item:with:colons'
@special_bone.tags.add 'item/with/slashes'
new_result = @special_bone.tags.each.to_a.sort
members_result = @special_bone.tags.members.sort
new_result == members_result
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

# ============================================================
# each_record vs load_multi consistency (reference SortedSet)
# Note: UnsortedSet does not have each_record since it requires
# a reference DataType. Using Customer.instances (a SortedSet)
# for this test as it has reference: true.
# ============================================================

## each_record yields same records as load_multi
each_record_ids = []
Customer.instances.each_record { |r| each_record_ids << r.custid if r.custid.start_with?(@test_prefix) }
each_record_ids.sort == @test_customers.map(&:custid).sort
#=> true

## each_record yields Horreum instances
records = []
Customer.instances.each_record { |r| records << r if r.custid.start_with?(@test_prefix) }
records.all? { |r| r.is_a?(Customer) }
#=> true

## each_record matches load_multi for loaded data
each_record_emails = []
Customer.instances.each_record { |r| each_record_emails << r.email if r.custid.start_with?(@test_prefix) }
load_multi_emails = Customer.load_multi(@test_customers.map(&:custid)).compact.map(&:email)
each_record_emails.sort == load_multi_emails.sort
#=> true

## each_record with batch_size matches load_multi
each_record_result = []
Customer.instances.each_record(batch_size: 2) { |r| each_record_result << r.custid if r.custid.start_with?(@test_prefix) }
load_multi_result = Customer.load_multi(@test_customers.map(&:custid)).compact.map(&:custid)
each_record_result.sort == load_multi_result.sort
#=> true

# Teardown: Clean up test data
@bone.tags.delete!
@empty_bone.tags.delete! if defined?(@empty_bone) && @empty_bone
@single_bone.tags.delete! if defined?(@single_bone) && @single_bone
@special_bone.tags.delete! if defined?(@special_bone) && @special_bone
@test_customers.each(&:destroy!) if defined?(@test_customers) && @test_customers
