# try/features/relationships/class_level_multi_index_rebuild_try.rb
#
# frozen_string_literal: true

# Tests for class-level multi_index rebuild functionality
# This feature allows rebuilding of multi-value indexes at the class level.
#
# The rebuild method:
# - Enumerates all instances via class_sorted_set :instances
# - Clears existing index sets using SCAN
# - Rebuilds indexes from current field values
# - Supports progress callbacks for monitoring

require_relative '../../support/helpers/test_helpers'

# Test class with class-level multi_index and instances collection
class ::RebuildCustomer < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :custid
  field :custid
  field :name
  field :tier  # premium, standard, free

  class_sorted_set :instances, reference: true  # Required for rebuild

  multi_index :tier, :tier_index
end

# Test class without instances collection (for prerequisite testing)
class ::RebuildCustomerNoInstances < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :custid
  field :custid
  field :tier

  multi_index :tier, :tier_index
end

# Clean up any stale data from previous runs
%w[premium standard free vip obsolete].each do |tier|
  RebuildCustomer.dbclient.del(RebuildCustomer.tier_index_for(tier).dbkey)
end
RebuildCustomer.instances.clear

# Setup - create test customers with various tiers
@cust1 = RebuildCustomer.new(custid: 'rc_001', name: 'Alice', tier: 'premium')
@cust1.save
@cust2 = RebuildCustomer.new(custid: 'rc_002', name: 'Bob', tier: 'standard')
@cust2.save
@cust3 = RebuildCustomer.new(custid: 'rc_003', name: 'Charlie', tier: 'premium')
@cust3.save
@cust4 = RebuildCustomer.new(custid: 'rc_004', name: 'Diana', tier: 'free')
@cust4.save
@cust5 = RebuildCustomer.new(custid: 'rc_005', name: 'Eve', tier: 'standard')
@cust5.save

# Register instances
RebuildCustomer.instances.add(@cust1.identifier)
RebuildCustomer.instances.add(@cust2.identifier)
RebuildCustomer.instances.add(@cust3.identifier)
RebuildCustomer.instances.add(@cust4.identifier)
RebuildCustomer.instances.add(@cust5.identifier)

# Manually add to indexes for initial state
@cust1.add_to_class_tier_index
@cust2.add_to_class_tier_index
@cust3.add_to_class_tier_index
@cust4.add_to_class_tier_index
@cust5.add_to_class_tier_index

# =============================================
# 1. Rebuild Method Existence
# =============================================

## Rebuild method is generated on the class
RebuildCustomer.respond_to?(:rebuild_tier_index)
#=> true

## Rebuild method accepts optional batch_size parameter
RebuildCustomer.method(:rebuild_tier_index).parameters.any? { |type, name| name == :batch_size }
#=> true

# =============================================
# 2. Basic Rebuild Functionality
# =============================================

## Verify initial index state before clearing
RebuildCustomer.tier_index_for('premium').size
#=> 2

## Clear indexes to simulate corruption or need for rebuild
%w[premium standard free].each do |tier|
  RebuildCustomer.tier_index_for(tier).clear
end
RebuildCustomer.tier_index_for('premium').size
#=> 0

## Rebuild returns count of processed objects
count = RebuildCustomer.rebuild_tier_index
count
#=> 5

## Premium tier has correct count after rebuild
RebuildCustomer.tier_index_for('premium').size
#=> 2

## Standard tier has correct count after rebuild
RebuildCustomer.tier_index_for('standard').size
#=> 2

## Free tier has correct count after rebuild
RebuildCustomer.tier_index_for('free').size
#=> 1

## Find all by tier works after rebuild
premiums = RebuildCustomer.find_all_by_tier('premium')
premiums.map(&:custid).sort
#=> ["rc_001", "rc_003"]

## All tiers are correctly populated
standards = RebuildCustomer.find_all_by_tier('standard')
standards.map(&:custid).sort
#=> ["rc_002", "rc_005"]

## Free tier query returns correct customer
frees = RebuildCustomer.find_all_by_tier('free')
frees.map(&:custid)
#=> ["rc_004"]

# =============================================
# 3. Rebuild with Progress Callback
# =============================================

## Clear indexes for progress test
%w[premium standard free].each do |tier|
  RebuildCustomer.tier_index_for(tier).clear
end

## Rebuild accepts progress block and store updates in instance variable
@progress_updates = []
count = RebuildCustomer.rebuild_tier_index { |progress| @progress_updates << progress.dup }
count
#=> 5

## Progress callback receives updates
@progress_updates.size > 0
#=> true

## Progress updates include loading phase and store in instance variable
@loading_updates = @progress_updates.select { |p| p[:phase] == :loading }
@loading_updates.any?
#=> true

## Progress updates include clearing phase
@clearing_updates = @progress_updates.select { |p| p[:phase] == :clearing }
@clearing_updates.any?
#=> true

## Progress updates include rebuilding phase and store in instance variable
@rebuilding_updates = @progress_updates.select { |p| p[:phase] == :rebuilding }
@rebuilding_updates.any?
#=> true

## Loading phase includes total count
@loading_updates.last[:total]
#=> 5

## Rebuilding phase shows completion
@rebuilding_updates.last[:current]
#=> 5

## Rebuilding phase total matches expected
@rebuilding_updates.last[:total]
#=> 5

# =============================================
# 4. Rebuild with Empty Instances Collection
# =============================================

## Class with empty instances has rebuild method
RebuildCustomerNoInstances.respond_to?(:rebuild_tier_index)
#=> true

## Class with empty instances returns 0 on rebuild (no objects to process)
result = RebuildCustomerNoInstances.rebuild_tier_index
result
#=> 0

# =============================================
# 5. Rebuild with Multiple Field Values
# =============================================

## Clear indexes before field value update test
%w[premium standard free vip].each do |tier|
  RebuildCustomer.tier_index_for(tier).clear
end

## Update customer tier values to VIP and save
@cust1.tier = 'vip'
@cust1.save
@cust3.tier = 'vip'
@cust3.save
true
#=> true

## Verify the tier change persisted by reloading
reloaded = RebuildCustomer.find_by_identifier(@cust1.identifier)
reloaded.tier
#=> "vip"

## Rebuild reflects updated field values
count = RebuildCustomer.rebuild_tier_index
count
#=> 5

## VIP tier has correct count after tier changes
RebuildCustomer.tier_index_for('vip').size
#=> 2

## Premium tier is empty after customers moved to VIP
RebuildCustomer.tier_index_for('premium').size
#=> 0

## Find all VIP customers works correctly
vips = RebuildCustomer.find_all_by_tier('vip')
vips.map(&:custid).sort
#=> ["rc_001", "rc_003"]

## Other tiers remain correct after partial update
RebuildCustomer.tier_index_for('standard').size
#=> 2

## Free tier remains correct
RebuildCustomer.tier_index_for('free').size
#=> 1

# =============================================
# 6. Rebuild with Orphaned Index Cleanup
# =============================================

## Create orphaned index entry (stale data from a tier that no longer exists)
RebuildCustomer.tier_index_for('obsolete').add('rc_001')
RebuildCustomer.tier_index_for('obsolete').size
#=> 1

## Rebuild cleans up orphaned indexes via SCAN
RebuildCustomer.rebuild_tier_index
RebuildCustomer.tier_index_for('obsolete').size
#=> 0

## Valid indexes still exist after cleanup
RebuildCustomer.tier_index_for('vip').size
#=> 2

# =============================================
# 7. Rebuild with nil/empty Field Values
# =============================================

## Create customer with nil tier
@cust_nil = RebuildCustomer.new(custid: 'rc_nil', name: 'NilTier', tier: nil)
@cust_nil.save
RebuildCustomer.instances.add(@cust_nil.identifier)
true
#=> true

## Create customer with empty tier
@cust_empty = RebuildCustomer.new(custid: 'rc_empty', name: 'EmptyTier', tier: '')
@cust_empty.save
RebuildCustomer.instances.add(@cust_empty.identifier)
true
#=> true

## Verify instances count is now 7
RebuildCustomer.instances.size
#=> 7

## Clear and rebuild
%w[vip standard free].each do |tier|
  RebuildCustomer.tier_index_for(tier).clear
end

## Rebuild processes all instances (including nil/empty)
count = RebuildCustomer.rebuild_tier_index
count
#=> 7

## Only valid tiers are indexed (nil/empty skipped)
total_indexed = RebuildCustomer.tier_index_for('vip').size +
                RebuildCustomer.tier_index_for('standard').size +
                RebuildCustomer.tier_index_for('free').size
total_indexed
#=> 5

## Nil tier index is empty
RebuildCustomer.tier_index_for('').size
#=> 0

# =============================================
# 8. Rebuild with Stale Instance References
# =============================================

## Add stale reference to instances collection
RebuildCustomer.instances.add('stale_customer_id')
RebuildCustomer.instances.size
#=> 8

## Rebuild handles stale references gracefully (loads 7 real objects, stale ID filtered out)
count = RebuildCustomer.rebuild_tier_index
count
#=> 7

## Index remains consistent despite stale reference (only 5 valid objects with tiers)
RebuildCustomer.tier_index_for('vip').size
#=> 2

# =============================================
# 9. Multiple Consecutive Rebuilds
# =============================================

## First rebuild (7 loadable objects from 8 instances)
count1 = RebuildCustomer.rebuild_tier_index
count1
#=> 7

## Second rebuild
count2 = RebuildCustomer.rebuild_tier_index
count2
#=> 7

## Third rebuild
count3 = RebuildCustomer.rebuild_tier_index
count3
#=> 7

## Index remains consistent after multiple rebuilds
RebuildCustomer.tier_index_for('vip').size
#=> 2

## All expected VIP customers still findable
vips = RebuildCustomer.find_all_by_tier('vip')
vips.map(&:custid).sort
#=> ["rc_001", "rc_003"]

# =============================================
# 10. Rebuild with batch_size Parameter
# =============================================

## Clear indexes
%w[vip standard free].each do |tier|
  RebuildCustomer.tier_index_for(tier).clear
end

## Rebuild with small batch size (7 loadable objects from 8 instances)
count = RebuildCustomer.rebuild_tier_index(batch_size: 1)
count
#=> 7

## Index works correctly with small batch size
RebuildCustomer.tier_index_for('vip').size
#=> 2

## Clear and rebuild with large batch size
%w[vip standard free].each do |tier|
  RebuildCustomer.tier_index_for(tier).clear
end

## Rebuild with large batch size (7 loadable objects from 8 instances)
count = RebuildCustomer.rebuild_tier_index(batch_size: 1000)
count
#=> 7

## Index works correctly with large batch size
RebuildCustomer.find_all_by_tier('standard').map(&:custid).sort
#=> ["rc_002", "rc_005"]

# Teardown
@cust1&.delete!
@cust2&.delete!
@cust3&.delete!
@cust4&.delete!
@cust5&.delete!
@cust_nil&.delete!
@cust_empty&.delete!

# Clean up index keys
%w[premium standard free vip obsolete].each do |tier|
  RebuildCustomer.dbclient.del(RebuildCustomer.tier_index_for(tier).dbkey)
end
RebuildCustomer.instances.clear
