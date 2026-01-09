# try/features/relationships/class_level_multi_index_auto_try.rb
#
# frozen_string_literal: true

# Tests for class-level multi_index auto-indexing and helper methods
#
# This file tests:
# 1. Auto-indexing on save - objects should automatically be added to class-level indexes
# 2. Index updates when field values change
# 3. Helper methods (update_all_indexes, remove_from_all_indexes, current_indexings)
#
# Auto-indexing for class-level indexes (within: :class) should work similarly
# to unique_index (within: nil), calling add_to_class_* methods on save.

require_relative '../../support/helpers/test_helpers'

# Test class for auto-indexing with class-level multi_index
class ::AutoIndexCustomer < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :custid
  field :custid
  field :name
  field :status
  field :tier

  # Class-level multi_index (within: :class is default)
  multi_index :status, :status_index

  # Explicit within: :class for second index
  multi_index :tier, :tier_index, within: :class

  # Track instances for rebuild testing
  class_sorted_set :instances, class: self, reference: true
end

# Clean up stale data from previous runs
%w[active pending inactive premium standard basic].each do |value|
  AutoIndexCustomer.dbclient.del(AutoIndexCustomer.status_index_for(value).dbkey)
  AutoIndexCustomer.dbclient.del(AutoIndexCustomer.tier_index_for(value).dbkey)
end
# Clean up any stale customer objects
%w[auto_001 auto_002 auto_003 auto_004 auto_nil auto_empty auto_ws].each do |custid|
  existing = AutoIndexCustomer.find_by_identifier(custid, check_exists: false)
  existing&.delete! if existing&.exists?
end

# =============================================
# 1. Auto-Indexing on Save Tests
# =============================================

## New object saved - auto-indexed in status_index
@auto1 = AutoIndexCustomer.new(custid: 'auto_001', name: 'AutoAlice', status: 'active', tier: 'premium')
@auto1.save
AutoIndexCustomer.status_index_for('active').members.include?('auto_001')
#=> true

## Auto-indexing works for tier_index too (explicit within: :class)
AutoIndexCustomer.tier_index_for('premium').members.include?('auto_001')
#=> true

## Second object saved - joins same status index
@auto2 = AutoIndexCustomer.new(custid: 'auto_002', name: 'AutoBob', status: 'active', tier: 'standard')
@auto2.save
AutoIndexCustomer.status_index_for('active').members.sort
#=> ["auto_001", "auto_002"]

## Different tier index is separate
AutoIndexCustomer.tier_index_for('standard').members
#=> ["auto_002"]

## Object with different status creates new index entry
@auto3 = AutoIndexCustomer.new(custid: 'auto_003', name: 'AutoCharlie', status: 'pending', tier: 'basic')
@auto3.save
AutoIndexCustomer.status_index_for('pending').members
#=> ["auto_003"]

## Active status index unchanged by new pending customer
AutoIndexCustomer.status_index_for('active').size
#=> 2

# =============================================
# 2. Query After Auto-Indexing
# =============================================

## find_all_by_status returns auto-indexed customers
active_customers = AutoIndexCustomer.find_all_by_status('active')
active_customers.map(&:custid).sort
#=> ["auto_001", "auto_002"]

## sample_from_status works with auto-indexed data
sample = AutoIndexCustomer.sample_from_status('active', 1)
['auto_001', 'auto_002'].include?(sample.first&.custid)
#=> true

## find_all_by_tier returns correct customers
premium_customers = AutoIndexCustomer.find_all_by_tier('premium')
premium_customers.map(&:custid)
#=> ["auto_001"]

# =============================================
# 3. Field Change and Index Update
# =============================================

## Change status field and save - verify old index is NOT automatically updated
# Note: auto_update_class_indexes calls add_to_class_*, which is idempotent
# but does NOT remove from old index. Manual update is needed for field changes.
@old_status = @auto1.status
@auto1.status = 'inactive'
@auto1.save

# After save, customer is added to new index
AutoIndexCustomer.status_index_for('inactive').members.include?('auto_001')
#=> true

## Old index still contains the entry (save doesn't auto-remove from old)
# This is expected behavior - save is idempotent add, not update
AutoIndexCustomer.status_index_for('active').members.include?('auto_001')
#=> true

## Use update_in_class_status_index to properly move between indexes
@auto1.update_in_class_status_index(@old_status)
AutoIndexCustomer.status_index_for('active').members.include?('auto_001')
#=> false

## Customer now only in inactive index
AutoIndexCustomer.status_index_for('inactive').members
#=> ["auto_001"]

# =============================================
# 4. Helper Methods - update_all_indexes
# =============================================

## update_all_indexes method exists
@auto2.respond_to?(:update_all_indexes)
#=> true

## update_all_indexes updates both status and tier indexes
@old_values = { status: @auto2.status, tier: @auto2.tier }
@auto2.status = 'pending'
@auto2.tier = 'premium'
@auto2.update_all_indexes(@old_values)

# Check status index updated
AutoIndexCustomer.status_index_for('active').members.include?('auto_002')
#=> false

## New status index contains customer
AutoIndexCustomer.status_index_for('pending').members.include?('auto_002')
#=> true

## Old tier index no longer contains customer
AutoIndexCustomer.tier_index_for('standard').members.include?('auto_002')
#=> false

## New tier index contains customer
AutoIndexCustomer.tier_index_for('premium').members.include?('auto_002')
#=> true

# =============================================
# 5. Helper Methods - remove_from_all_indexes
# =============================================

## remove_from_all_indexes method exists
@auto3.respond_to?(:remove_from_all_indexes)
#=> true

## Verify customer is in indexes before removal
[
  AutoIndexCustomer.status_index_for('pending').members.include?('auto_003'),
  AutoIndexCustomer.tier_index_for('basic').members.include?('auto_003')
]
#=> [true, true]

## remove_from_all_indexes removes from all class-level indexes
@auto3.remove_from_all_indexes
[
  AutoIndexCustomer.status_index_for('pending').members.include?('auto_003'),
  AutoIndexCustomer.tier_index_for('basic').members.include?('auto_003')
]
#=> [false, false]

# =============================================
# 6. Helper Methods - current_indexings
# =============================================

## current_indexings method exists
@auto1.respond_to?(:current_indexings)
#=> true

## Re-add auto1 to indexes for testing current_indexings
@auto1.add_to_class_status_index
@auto1.add_to_class_tier_index
@indexings = @auto1.current_indexings
@indexings.length
#=> 2

## current_indexings returns correct info for status_index
@status_indexing = @indexings.find { |i| i[:index_name] == :status_index }
[@status_indexing[:field], @status_indexing[:cardinality], @status_indexing[:type]]
#=> [:status, :multi, "multi_index"]

## current_indexings returns correct info for tier_index
@tier_indexing = @indexings.find { |i| i[:index_name] == :tier_index }
[@tier_indexing[:field], @tier_indexing[:cardinality], @tier_indexing[:type]]
#=> [:tier, :multi, "multi_index"]

## current_indexings shows scope_class for class-level indexes
@status_indexing[:scope_class]
#=> "class"

# =============================================
# 7. Helper Methods - indexed_in?
# =============================================

## indexed_in? method exists
@auto1.respond_to?(:indexed_in?)
#=> true

## indexed_in? returns true for indexes where customer is present
@auto1.indexed_in?(:status_index)
#=> true

## indexed_in? returns true for tier_index too
@auto1.indexed_in?(:tier_index)
#=> true

## indexed_in? returns false for non-existent index
@auto1.indexed_in?(:nonexistent_index)
#=> false

## After removal, indexed_in? returns false
@auto1.remove_from_class_status_index
@auto1.indexed_in?(:status_index)
#=> false

# =============================================
# 8. Delete and Index Cleanup
# =============================================

## Create a new customer for delete testing
@auto4 = AutoIndexCustomer.new(custid: 'auto_004', name: 'AutoDiana', status: 'active', tier: 'standard')
@auto4.save
AutoIndexCustomer.status_index_for('active').members.include?('auto_004')
#=> true

## Delete does NOT automatically remove from indexes (by design)
# Applications should call remove_from_all_indexes before delete if needed
@auto4.delete!
AutoIndexCustomer.status_index_for('active').members.include?('auto_004')
#=> true

## Manual cleanup required after delete
# Note: This tests that stale entries exist until explicitly cleaned
# The find_by methods handle stale entries gracefully
stale_customer = AutoIndexCustomer.find_by_identifier('auto_004')
stale_customer
#=> nil

# =============================================
# 9. Edge Cases
# =============================================

## Nil field value - should not be indexed
@auto_nil = AutoIndexCustomer.new(custid: 'auto_nil', name: 'NilStatus', status: nil, tier: 'basic')
@auto_nil.save
# Should not create an entry in the nil index (empty string key)
AutoIndexCustomer.status_index_for('').members.include?('auto_nil')
#=> false

## Empty string field value - should not be indexed
@auto_empty = AutoIndexCustomer.new(custid: 'auto_empty', name: 'EmptyStatus', status: '', tier: 'basic')
@auto_empty.save
AutoIndexCustomer.status_index_for('').members.include?('auto_empty')
#=> false

## Whitespace-only field value - should not be indexed
@auto_ws = AutoIndexCustomer.new(custid: 'auto_ws', name: 'WSStatus', status: '   ', tier: 'basic')
@auto_ws.save
AutoIndexCustomer.status_index_for('   ').members.include?('auto_ws')
#=> false

# =============================================
# 10. Idempotent Save Behavior
# =============================================

## Saving same object multiple times doesn't duplicate index entries
@auto2.save
@auto2.save
@auto2.save
# Should still only have one entry
AutoIndexCustomer.status_index_for(@auto2.status).members.count { |m| m == 'auto_002' }
#=> 1

## UnsortedSet inherently prevents duplicates
AutoIndexCustomer.status_index_for('pending').size
#=> 1

# Teardown
# Clean up test objects
[@auto1, @auto2, @auto3, @auto_nil, @auto_empty, @auto_ws].compact.each do |obj|
  obj.delete! if obj.respond_to?(:exists?) && obj.exists?
end

# Clean up index keys
%w[active pending inactive premium standard basic].each do |value|
  AutoIndexCustomer.dbclient.del(AutoIndexCustomer.status_index_for(value).dbkey)
  AutoIndexCustomer.dbclient.del(AutoIndexCustomer.tier_index_for(value).dbkey)
end

# Clean up edge case indexes
['', '   '].each do |value|
  AutoIndexCustomer.dbclient.del(AutoIndexCustomer.status_index_for(value).dbkey)
end

# Clean up instances collection
AutoIndexCustomer.instances.clear if AutoIndexCustomer.respond_to?(:instances)
