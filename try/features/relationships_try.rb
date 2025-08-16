# try/features/relationships_try.rb

require_relative '../helpers/test_helpers'

# Test classes for relationship functionality
class TestCustomer < Familia::Horreum
  feature :relatable_objects
  feature :relationships

  identifier_field :custid
  field :custid
  field :name

  sorted_set :custom_domains
end

class TestDomain < Familia::Horreum
  feature :relatable_objects
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at
  field :permission_level

  # Global registry of all domains
  tracked_in :values, type: :sorted_set, score: :created_at, cascade: :delete

  # Fast lookup indexes
  indexed_by :display_domain, in: :display_domains, finder: true
  indexed_by :domain_id, in: :domain_id_index, finder: true

  # Membership in customer's collection
  member_of TestCustomer, :custom_domains, key: :display_domain
end

class TestTag < Familia::Horreum
  feature :relatable_objects
  feature :relationships

  identifier_field :name
  field :name
  field :created_at

  # Simple set membership
  tracked_in :all_tags, type: :set, cascade: :delete
end

# Setup
@customer = TestCustomer.new(custid: 'test_cust_123', name: 'Test Customer')
@domain = TestDomain.new(
  domain_id: 'dom_456',
  display_domain: 'example.com',
  created_at: Time.now.to_i,
  permission_level: 'admin'
)
@tag = TestTag.new(name: 'important', created_at: Time.now.to_i)

# =============================================
# 1. DSL Method Availability Tests
# =============================================

## Class responds to tracked_in DSL method
TestDomain.respond_to?(:tracked_in)
#=> true

## Class responds to indexed_by DSL method
TestDomain.respond_to?(:indexed_by)
#=> true

## Class responds to member_of DSL method
TestDomain.respond_to?(:member_of)
#=> true

## Class maintains relationships metadata
TestDomain.relationships.size
#=> 4

## First relationship is TrackedInRelationship
TestDomain.relationships[0].class.name
#=> "Familia::Features::Relationships::TrackedInRelationship"

## Second relationship is IndexedByRelationship
TestDomain.relationships[1].class.name
#=> "Familia::Features::Relationships::IndexedByRelationship"

## Class creates required data structures for tracked_in
TestDomain.respond_to?(:values)
#=> true

## Values is a SortedSet
TestDomain.values.class.name
#=> "Familia::SortedSet"

## Class creates required data structures for indexed_by
TestDomain.respond_to?(:display_domains)
#=> true

## Display domains is a HashKey
TestDomain.display_domains.class.name
#=> "Familia::HashKey"

# =============================================
# 2. Generated Methods Tests
# =============================================

## tracked_in generates add_to_collection method
TestDomain.respond_to?(:add_to_values)
#=> true

## tracked_in generates remove_from_collection method
TestDomain.respond_to?(:remove_from_values)
#=> true

## tracked_in generates update_score method for sorted sets
TestDomain.respond_to?(:update_score_in_values)
#=> true

## indexed_by with finder:true generates finder method
TestDomain.respond_to?(:from_display_domain)
#=> true

## indexed_by with finder:true generates second finder method
TestDomain.respond_to?(:from_domain_id)
#=> true

## member_of generates instance methods on owned object
@domain.respond_to?(:add_to_testcustomer)
#=> true

## member_of generates remove method on owned object
@domain.respond_to?(:remove_from_testcustomer)
#=> true

# =============================================
# 3. Lifecycle Hook Tests
# =============================================

## Object has relationships maintenance methods
@domain.respond_to?(:maintain_relationships, true)
#=> true

## Save operation adds to tracked collections
@domain.save
TestDomain.values.member?(@domain.identifier)
#=> true

## Save operation updates indexes
TestDomain.display_domains.get('example.com')
#=> 'dom_456'

## Save operation updates domain_id index
TestDomain.domain_id_index.get('dom_456')
#=> 'dom_456'

## Set membership works for simple sets
@tag.save
TestTag.all_tags.member?(@tag.identifier)
#=> true

# =============================================
# 4. Finder Method Tests
# =============================================

## Generated finder works for valid values
found_domain = TestDomain.from_display_domain('example.com')
found_domain.domain_id
#=> 'dom_456'

## Generated finder returns nil for invalid values
TestDomain.from_display_domain('nonexistent.com')
#=> nil

## Generated finder works for domain_id
found_by_id = TestDomain.from_domain_id('dom_456')
found_by_id.display_domain
#=> 'example.com'

# =============================================
# 5. Collection Management Tests
# =============================================

## Manual add to collection works
@customer.save
TestDomain.add_to_values(@domain)
TestDomain.values.member?(@domain.identifier)
#=> true

## Manual remove from collection works
TestDomain.remove_from_values(@domain)
TestDomain.values.member?(@domain.identifier)
#=> false

## Re-add for further tests
TestDomain.add_to_values(@domain)

## Score update works for sorted sets
TestDomain.update_score_in_values(@domain, 999)
TestDomain.values.score(@domain.identifier)
#=> 999.0

# =============================================
# 6. Member Relationship Tests
# =============================================

## Add to customer collection works
@domain.add_to_testcustomer(@customer)
@customer.custom_domains.member?(@domain.display_domain)
#=> true

## Remove from customer collection works
@domain.remove_from_testcustomer(@customer)
@customer.custom_domains.member?(@domain.display_domain)
#=> false

# =============================================
# 7. Cascade Deletion Tests
# =============================================

## Objects are in collections before destruction
@domain.save
@tag.save
[TestDomain.values.member?(@domain.identifier), TestTag.all_tags.member?(@tag.identifier)]
#=> [true, true]

## Cascade delete removes from collections
@domain.destroy!
TestDomain.values.member?(@domain.identifier)
#=> false

## Cascade delete removes from indexes
TestDomain.display_domains.get('example.com')
#=> nil

## Cascade delete works for sets too
@tag.destroy!
TestTag.all_tags.member?(@tag.identifier)
#=> false

# =============================================
# 8. Error Handling Tests
# =============================================

## RelationshipError is available
Familia::Features::Relationships::RelationshipError.ancestors.include?(Familia::Problem)
#=> true

# =============================================
# 9. Permission Encoding Helper Tests (Future)
# =============================================

## Permission levels constant exists
TestDomain.new.respond_to?(:permission_encode, true) || "not implemented yet"
#=:> String

# Cleanup
@customer.destroy! if @customer&.exists?
@domain.destroy! if @domain&.exists?
@tag.destroy! if @tag&.exists?

# Clear any remaining test data
TestDomain.values.clear rescue nil
TestDomain.display_domains.clear rescue nil
TestDomain.domain_id_index.clear rescue nil
TestTag.all_tags.clear rescue nil
TestCustomer.custom_domains.clear rescue nil
