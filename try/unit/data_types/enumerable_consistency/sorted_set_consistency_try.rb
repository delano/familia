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

# Setup: Create test customers for each_record testing (reference SortedSet)
@test_prefix = "sorted_set_consistency_#{Time.now.to_i}"
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

## SortedSet#each.to_a matches members (sorted comparison)
new_result = @bone.metrics.each.to_a.sort
members_result = @bone.metrics.members.sort
new_result == members_result
#=> true

## SortedSet#each.to_a has same count as members
@bone.metrics.each.to_a.size == @bone.metrics.members.size
#=> true

## SortedSet#each.to_a count matches element_count
@bone.metrics.each.to_a.size == @bone.metrics.element_count
#=> true

## SortedSet#each.to_a includes all members
members_list = @bone.metrics.members
each_members = @bone.metrics.each.to_a
(members_list - each_members).empty?
#=> true

## SortedSet#each.to_a has no extra members beyond members
each_members = @bone.metrics.each.to_a
members_list = @bone.metrics.members
(each_members - members_list).empty?
#=> true

# ============================================================
# map consistency with collectraw
# ============================================================

## SortedSet#map matches members with identity transform (sorted)
new_result = @bone.metrics.map { |x| x }.sort
members_result = @bone.metrics.members.sort
new_result == members_result
#=> true

## SortedSet#map with upcase matches members transformation
new_result = @bone.metrics.map { |x| x.upcase }.sort
members_result = @bone.metrics.members.map(&:upcase).sort
new_result == members_result
#=> true

## SortedSet#select matches members filtering
new_result = @bone.metrics.select { |x| x.start_with?('item_') }.sort
members_result = @bone.metrics.members.select { |m| m.start_with?('item_') }.sort
new_result == members_result
#=> true

# ============================================================
# Batch size variations
# ============================================================

## SortedSet#each with batch_size=1 matches members
new_result = @bone.metrics.each(batch_size: 1).to_a.sort
members_result = @bone.metrics.members.sort
new_result == members_result
#=> true

## SortedSet#each with batch_size=5 matches members
new_result = @bone.metrics.each(batch_size: 5).to_a.sort
members_result = @bone.metrics.members.sort
new_result == members_result
#=> true

## SortedSet#each with batch_size=10 matches members
new_result = @bone.metrics.each(batch_size: 10).to_a.sort
members_result = @bone.metrics.members.sort
new_result == members_result
#=> true

## SortedSet#each with batch_size=50 matches members
new_result = @bone.metrics.each(batch_size: 50).to_a.sort
members_result = @bone.metrics.members.sort
new_result == members_result
#=> true

## SortedSet#each with batch_size=1000 (larger than set) matches members
new_result = @bone.metrics.each(batch_size: 1000).to_a.sort
members_result = @bone.metrics.members.sort
new_result == members_result
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

## SortedSet#members has no duplicates
members_result = @bone.metrics.members
members_result.size == members_result.uniq.size
#=> true

## SortedSet total count is consistent across methods
count_via_each = @bone.metrics.each.to_a.size
count_via_members = @bone.metrics.members.size
count_via_method = @bone.metrics.element_count
count_via_each == count_via_members && count_via_members == count_via_method
#=> true

# ============================================================
# Edge cases
# ============================================================

## Empty SortedSet: each.to_a matches members
@empty_bone = Bone.new 'sorted_set_consistency_empty_test'
new_result = @empty_bone.metrics.each.to_a
members_result = @empty_bone.metrics.members
new_result == members_result && new_result == []
#=> true

## Single element SortedSet: each.to_a matches members
@single_bone = Bone.new 'sorted_set_consistency_single_test'
@single_bone.metrics.add 'only_item', 42.0
new_result = @single_bone.metrics.each.to_a
members_result = @single_bone.metrics.members
new_result == members_result
#=> true

## SortedSet with special characters: each.to_a matches members
@special_bone = Bone.new 'sorted_set_consistency_special_test'
@special_bone.metrics.add 'item with spaces', 1.0
@special_bone.metrics.add 'item:with:colons', 2.0
@special_bone.metrics.add 'item/with/slashes', 3.0
new_result = @special_bone.metrics.each.to_a.sort
members_result = @special_bone.metrics.members.sort
new_result == members_result
#=> true

# ============================================================
# each_record vs load_multi consistency (reference SortedSet)
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
@bone.metrics.delete!
@empty_bone.metrics.delete! if defined?(@empty_bone) && @empty_bone
@single_bone.metrics.delete! if defined?(@single_bone) && @single_bone
@special_bone.metrics.delete! if defined?(@special_bone) && @special_bone
@test_customers.each(&:destroy!) if defined?(@test_customers) && @test_customers
