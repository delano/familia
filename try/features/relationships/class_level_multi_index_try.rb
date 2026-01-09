# try/features/relationships/class_level_multi_index_try.rb
#
# frozen_string_literal: true

# Tests for class-level multi_index functionality (within: :class)
# This feature allows multi-value indexes at the class level, similar to how
# unique_index works without a within: parameter.
#
# Example: multi_index :role, :role_index  (within: :class is the default)
# Creates class methods like Customer.find_all_by_role('admin')

require_relative '../../support/helpers/test_helpers'

# Test class with class-level multi_index
class ::ClassLevelCustomer < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :custid
  field :custid
  field :name
  field :role
  field :region

  # Class-level multi_index (default: within: :class)
  multi_index :role, :role_index

  # Explicit within: :class (same behavior)
  multi_index :region, :region_index, within: :class

  # Multi_index with query: false
  multi_index :name, :name_index, query: false
end

# Clean up any stale data from previous runs
%w[admin user superadmin].each do |role|
  ClassLevelCustomer.dbclient.del(ClassLevelCustomer.role_index_for(role).dbkey)
end
%w[west east].each do |region|
  ClassLevelCustomer.dbclient.del(ClassLevelCustomer.region_index_for(region).dbkey)
end

# Setup - create test customers with various roles and regions
@cust1 = ClassLevelCustomer.new(custid: 'cust_001', name: 'Alice', role: 'admin', region: 'west')
@cust1.save
@cust2 = ClassLevelCustomer.new(custid: 'cust_002', name: 'Bob', role: 'user', region: 'east')
@cust2.save
@cust3 = ClassLevelCustomer.new(custid: 'cust_003', name: 'Charlie', role: 'admin', region: 'west')
@cust3.save
@cust4 = ClassLevelCustomer.new(custid: 'cust_004', name: 'Diana', role: 'user', region: 'east')
@cust4.save

# =============================================
# 1. Class-Level Multi-Index Registration
# =============================================

## Class-level multi_index relationships are registered
ClassLevelCustomer.indexing_relationships.length
#=> 3

## First multi_index relationship has correct configuration
config = ClassLevelCustomer.indexing_relationships.first
[config.field, config.index_name, config.cardinality, config.within]
#=> [:role, :role_index, :multi, :class]

## Second multi_index relationship (explicit within: :class)
config = ClassLevelCustomer.indexing_relationships[1]
[config.field, config.index_name, config.cardinality, config.within]
#=> [:region, :region_index, :multi, :class]

## Third multi_index has query disabled
config = ClassLevelCustomer.indexing_relationships.last
[config.field, config.index_name, config.query]
#=> [:name, :name_index, false]

# =============================================
# 2. Generated Class Methods
# =============================================

## Factory method is generated on the class
ClassLevelCustomer.respond_to?(:role_index_for)
#=> true

## Factory method returns UnsortedSet
ClassLevelCustomer.role_index_for('admin').class
#=> Familia::UnsortedSet

## Query method find_all_by_role is generated
ClassLevelCustomer.respond_to?(:find_all_by_role)
#=> true

## Query method sample_from_role is generated
ClassLevelCustomer.respond_to?(:sample_from_role)
#=> true

## Rebuild method is generated
ClassLevelCustomer.respond_to?(:rebuild_role_index)
#=> true

## No query methods when query: false
ClassLevelCustomer.respond_to?(:find_all_by_name)
#=> false

## But factory method is still available even with query: false
ClassLevelCustomer.respond_to?(:name_index_for)
#=> true

# =============================================
# 3. Generated Instance Methods
# =============================================

## Add method is generated on instances
@cust1.respond_to?(:add_to_class_role_index)
#=> true

## Remove method is generated on instances
@cust1.respond_to?(:remove_from_class_role_index)
#=> true

## Update method is generated on instances
@cust1.respond_to?(:update_in_class_role_index)
#=> true

# =============================================
# 4. Manual Indexing Operations
# =============================================

## Add customer to class index manually
@cust1.add_to_class_role_index
ClassLevelCustomer.role_index_for('admin').members.include?('cust_001')
#=> true

## Add multiple customers to index
@cust2.add_to_class_role_index
@cust3.add_to_class_role_index
@cust4.add_to_class_role_index
ClassLevelCustomer.role_index_for('admin').size
#=> 2

## Users index has correct members
ClassLevelCustomer.role_index_for('user').size
#=> 2

# =============================================
# 5. Query Operations
# =============================================

## find_all_by_role returns all matching customers
admins = ClassLevelCustomer.find_all_by_role('admin')
admins.map(&:custid).sort
#=> ["cust_001", "cust_003"]

## find_all_by_role returns empty array for non-existent role
ClassLevelCustomer.find_all_by_role('superadmin')
#=> []

## sample_from_role returns random customer
sample = ClassLevelCustomer.sample_from_role('admin', 1)
['cust_001', 'cust_003'].include?(sample.first&.custid)
#=> true

## sample_from_role with count > 1
samples = ClassLevelCustomer.sample_from_role('user', 2)
samples.length
#=> 2

# =============================================
# 6. Update Operations
# =============================================

## Update method moves customer between indexes
old_role = @cust1.role
@cust1.role = 'superadmin'
@cust1.update_in_class_role_index(old_role)
ClassLevelCustomer.role_index_for('admin').members.include?('cust_001')
#=> false

## Customer is now in new index
ClassLevelCustomer.role_index_for('superadmin').members.include?('cust_001')
#=> true

# =============================================
# 7. Remove Operations
# =============================================

## Remove customer from index
@cust4.remove_from_class_role_index
ClassLevelCustomer.role_index_for('user').members.include?('cust_004')
#=> false

## Other customer in same index is unaffected
ClassLevelCustomer.role_index_for('user').members.include?('cust_002')
#=> true

# =============================================
# 8. Redis Key Pattern
# =============================================

## Redis key follows class-level pattern
index_set = ClassLevelCustomer.role_index_for('admin')
index_set.dbkey
#=~ /classlevelcustomer:role_index:admin/

## Different field values have different keys
key1 = ClassLevelCustomer.role_index_for('admin').dbkey
key2 = ClassLevelCustomer.role_index_for('user').dbkey
key1 != key2
#=> true

# =============================================
# 9. Region Index (explicit within: :class)
# =============================================

## Verify region field values before indexing
[@cust1.region, @cust2.region, @cust3.region]
#=> ["west", "east", "west"]

## Verify the add_to_class_region_index method exists
@cust1.respond_to?(:add_to_class_region_index)
#=> true

## Debug: Check what the region_index IndexingRelationship looks like
region_config = ClassLevelCustomer.indexing_relationships.find { |c| c.index_name == :region_index }
[region_config.field, region_config.index_name, region_config.cardinality]
#=> [:region, :region_index, :multi]

## Region index is auto-populated on save (cust1 and cust3 are 'west')
# Note: Auto-indexing is now enabled for class-level multi_index
ClassLevelCustomer.region_index_for('west').members.sort
#=> ["cust_001", "cust_003"]

## East region is also auto-populated (cust2 and cust4 are 'east')
ClassLevelCustomer.region_index_for('east').members.sort
#=> ["cust_002", "cust_004"]

## Manual add_to is idempotent (no duplicate entries)
@cust1.add_to_class_region_index
ClassLevelCustomer.region_index_for('west').members.sort
#=> ["cust_001", "cust_003"]

## Verify all region indexes after auto-indexing
[ClassLevelCustomer.region_index_for('west').members.sort, ClassLevelCustomer.region_index_for('east').members.sort]
#=> [["cust_001", "cust_003"], ["cust_002", "cust_004"]]

## Query by region works
west_customers = ClassLevelCustomer.find_all_by_region('west')
west_customers.map(&:custid).sort
#=> ["cust_001", "cust_003"]

## East region also works
east_customers = ClassLevelCustomer.find_all_by_region('east')
east_customers.map(&:custid).sort
#=> ["cust_002", "cust_004"]

# =============================================
# 10. Edge Cases and Nil Handling
# =============================================

## Adding to index with nil field value does nothing (no error)
@cust_nil = ClassLevelCustomer.new(custid: 'cust_nil', name: 'NilRole', role: nil, region: 'west')
@cust_nil.save
result = @cust_nil.add_to_class_role_index
result.nil?
#=> true

## Nil role customer is not in any role index
ClassLevelCustomer.role_index_for('').members.include?('cust_nil')
#=> false

## Adding to index with empty string field value does nothing
@cust_empty = ClassLevelCustomer.new(custid: 'cust_empty', name: 'EmptyRole', role: '', region: 'east')
@cust_empty.save
result = @cust_empty.add_to_class_role_index
result.nil?
#=> true

## Adding to index with whitespace-only field value does nothing
@cust_whitespace = ClassLevelCustomer.new(custid: 'cust_ws', name: 'WhitespaceRole', role: '   ', region: 'east')
@cust_whitespace.save
result = @cust_whitespace.add_to_class_role_index
result.nil?
#=> true

## find_all_by_* with nil value returns empty array
ClassLevelCustomer.find_all_by_role(nil)
#=> []

## find_all_by_* with empty string returns empty array
ClassLevelCustomer.find_all_by_role('')
#=> []

## sample_from_* with nil value returns empty array
ClassLevelCustomer.sample_from_role(nil, 1)
#=> []

## sample_from_* with empty string returns empty array
ClassLevelCustomer.sample_from_role('', 1)
#=> []

## sample_from_* with count=0 returns empty array
ClassLevelCustomer.sample_from_role('admin', 0)
#=> []

## Update with same old and new value does nothing (no-op)
# First ensure cust3 is in the admin index
@cust3.role = 'admin'
@cust3.add_to_class_role_index
admin_count_before = ClassLevelCustomer.role_index_for('admin').size
@cust3.update_in_class_role_index('admin')  # same value
admin_count_after = ClassLevelCustomer.role_index_for('admin').size
admin_count_before == admin_count_after
#=> true

## Update when field becomes nil removes from old index only
@cust_update = ClassLevelCustomer.new(custid: 'cust_update', name: 'WillBeNil', role: 'tempuser', region: 'west')
@cust_update.save
@cust_update.add_to_class_role_index
ClassLevelCustomer.role_index_for('tempuser').members.include?('cust_update')
#=> true

## After setting role to nil and updating, customer is removed from old index
old_role = @cust_update.role
@cust_update.role = nil
@cust_update.update_in_class_role_index(old_role)
ClassLevelCustomer.role_index_for('tempuser').members.include?('cust_update')
#=> false

## Update with nil old_value returns early (no-op)
@cust3.role = 'admin'
result = @cust3.update_in_class_role_index(nil)
result.nil?
#=> true

# Teardown
@cust1.delete!
@cust2.delete!
@cust3.delete!
@cust4.delete!
@cust_nil&.delete!
@cust_empty&.delete!
@cust_whitespace&.delete!
@cust_update&.delete!
# Clean up index keys
ClassLevelCustomer.dbclient.del(ClassLevelCustomer.role_index_for('admin').dbkey)
ClassLevelCustomer.dbclient.del(ClassLevelCustomer.role_index_for('user').dbkey)
ClassLevelCustomer.dbclient.del(ClassLevelCustomer.role_index_for('superadmin').dbkey)
ClassLevelCustomer.dbclient.del(ClassLevelCustomer.role_index_for('tempuser').dbkey)
ClassLevelCustomer.dbclient.del(ClassLevelCustomer.region_index_for('west').dbkey)
ClassLevelCustomer.dbclient.del(ClassLevelCustomer.region_index_for('east').dbkey)
