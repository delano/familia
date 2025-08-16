# try/features/relationships_try.rb

require_relative '../helpers/test_helpers'

# Test classes for Familia v2 relationship functionality
class TestCustomer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid
  field :name

  sorted_set :custom_domains
end

class TestDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at
  field :permission_level

  # Multi-presence tracking with score encoding
  tracked_in TestCustomer, :domains, score: -> { permission_encode(created_at, permission_level || :read) }
  tracked_in :global, :all_domains, score: :created_at

  # O(1) lookups with Redis hashes
  indexed_by :display_domain, :domain_index, context: TestCustomer, finder: true
  indexed_by :domain_id, :global_domain_index, context: :global, finder: true

  # Context-aware membership (collision-free naming)
  member_of TestCustomer, :domains
end

class TestTeam < Familia::Horreum
  feature :relationships

  identifier_field :team_id
  field :team_id
  field :name

  sorted_set :domains
end

class TestTag < Familia::Horreum
  feature :relationships

  identifier_field :name
  field :name
  field :created_at

  # Global tracking
  tracked_in :global, :all_tags, score: :created_at
end

# Setup
@customer = TestCustomer.new(custid: 'test_cust_123', name: 'Test Customer')
@team = TestTeam.new(team_id: 'team_456', name: 'Test Team')
@domain = TestDomain.new(
  domain_id: 'dom_789',
  display_domain: 'example.com',
  created_at: Time.now.to_i,
  permission_level: :write
)
@tag = TestTag.new(name: 'important', created_at: Time.now.to_i)

# =============================================
# 1. V2 Feature Integration Tests
# =============================================

## Single feature includes all relationship functionality
TestDomain.included_modules.map(&:name).include?('Familia::Features::Relationships')
#=> true

## Score encoding functionality is available
@domain.respond_to?(:encode_score)
#=> true

## Permission encoding functionality is available
@domain.respond_to?(:permission_encode)
#=> true

## Redis operations functionality is available
@domain.respond_to?(:atomic_operation)
#=> true

## Identifier method works (wraps identifier_field)
TestDomain.identifier_field
#=> :domain_id

## Identifier instance method works
@domain.identifier
#=> 'dom_789'

# =============================================
# 2. Score Encoding Tests
# =============================================

## Permission encoding creates proper score
@score = @domain.permission_encode(Time.now, :write)
@score.to_s.match?(/\d+\.\d+/)
#=> true

## Permission decoding extracts correct permission
decoded = @domain.permission_decode(@score)
decoded[:permission]
#=> :write

## Score encoding preserves timestamp ordering
@early_score = @domain.encode_score(Time.now - 3600, 100)  # 1 hour ago
@late_score = @domain.encode_score(Time.now, 100)
@late_score > @early_score
#=> true

# =============================================
# 3. Tracking Relationships (tracked_in)
# =============================================

## Save operation manages tracking relationships
@customer.save
@domain.save

## Customer has domains collection (generated method)
@customer.respond_to?(:domains)
#=> true

## Customer.domains returns SortedSet
@customer.domains.class.name
#=> "Familia::SortedSet"

## Customer can add domains (generated method)
@customer.respond_to?(:add_domain)
#=> true

## Customer can remove domains (generated method)
@customer.respond_to?(:remove_domain)
#=> true

## Domain can check membership in customer domains (collision-free naming)
@domain.respond_to?(:in_testcustomer_domains?)
#=> true

## Domain can add itself to customer domains (collision-free naming)
@domain.respond_to?(:add_to_testcustomer_domains)
#=> true

## Domain can remove itself from customer domains (collision-free naming)
@domain.respond_to?(:remove_from_testcustomer_domains)
#=> true

## Add domain to customer collection
@domain.add_to_testcustomer_domains(@customer)
@domain.in_testcustomer_domains?(@customer)
#=> true

## Score is properly encoded with permission
score = @domain.score_in_testcustomer_domains(@customer)
decoded = @domain.permission_decode(score)
decoded[:permission]
#=> :write

# =============================================
# 4. Indexing Relationships (indexed_by)
# =============================================

## Customer has generated finder method for domain index
@customer.respond_to?(:find_by_display_domain)
#=> true

## Domain can add itself to customer's domain index
@domain.respond_to?(:add_to_testcustomer_domain_index)
#=> true

## Adding to index works
@domain.add_to_testcustomer_domain_index(@customer)
found = @customer.find_by_display_domain('example.com')
found&.domain_id
#=> 'dom_789'

## Global indexing works
TestDomain.respond_to?(:find_by_domain_id_globally)
#=> true

## Add to global index
@domain.add_to_global_global_domain_index
found_global = TestDomain.find_by_domain_id_globally('dom_789')
found_global&.display_domain
#=> 'example.com'

# =============================================
# 5. Membership Relationships (member_of)
# =============================================

## Member_of generates collision-free methods with collection names
@domain.respond_to?(:add_to_testcustomer_domains)
#=> true

## Member_of supports multiple collections without conflicts
TestDomain.member_of TestTeam, :domains  # Add second member_of
@domain.respond_to?(:add_to_testteam_domains)
#=> true

## Both customer and team domain methods exist without collision
[@domain.respond_to?(:add_to_testcustomer_domains), @domain.respond_to?(:add_to_testteam_domains)]
#=> [true, true]

## Adding to different collections works independently
@team.save
@domain.add_to_testteam_domains(@team)
[@domain.in_testcustomer_domains?(@customer), @domain.in_testteam_domains?(@team)]
#=> [true, true]

# =============================================
# 6. Multi-Presence Support
# =============================================

## Object can exist in multiple collections simultaneously
membership_collections = @domain.membership_collections
membership_collections.length >= 2
#=> true

## Relationship status shows comprehensive membership info
status = @domain.relationship_status
status[:membership_collections].length >= 2
#=> true

## Object can be removed from specific collections without affecting others
@domain.remove_from_testcustomer_domains(@customer)
[@domain.in_testcustomer_domains?(@customer), @domain.in_testteam_domains?(@team)]
#=> [false, true]

# =============================================
# 7. Redis-Native Operations
# =============================================

## Atomic operations work for multi-collection updates
@domain.update_multiple_presence([
  { key: "testcustomer:#{@customer.custid}:domains", score: @domain.current_score },
  { key: "testteam:#{@team.team_id}:domains", score: @domain.current_score }
], :add, @domain.identifier)

## Both collections now contain the domain
[@domain.in_testcustomer_domains?(@customer), @domain.in_testteam_domains?(@team)]
#=> [true, true]

# =============================================
# 8. Set Operations and Querying
# =============================================

## Union operations work across collections
accessible_domains = TestDomain.union_collections([
  { owner: @customer, collection: :domains },
  { owner: @team, collection: :domains }
], ttl: 300)
accessible_domains.class.name
#=> "Familia::SortedSet"

## Union contains our domain
accessible_domains.member?(@domain.identifier)
#=> true

## Permission filtering works in queries
write_domains = TestDomain.query_collections([
  { owner: @customer, collection: :domains },
  { owner: @team, collection: :domains }
], { min_permission: :write }, 300)
write_domains.member?(@domain.identifier)
#=> true

# =============================================
# 9. Cascade Operations
# =============================================

## Cascade dry run shows impact without executing
preview = @domain.cascade_dry_run
preview[:affected_keys].length > 0
#=> true

## Object cleanup removes from all relationships
@domain.cleanup_all_relationships!
[@domain.in_testcustomer_domains?(@customer), @domain.in_testteam_domains?(@team)]
#=> [false, false]

## Indexes are also cleaned up
@customer.find_by_display_domain('example.com')
#=> nil

# =============================================
# 10. Global Tag Tracking Test
# =============================================

## Tag can be tracked globally
@tag.save
@tag.add_to_global_all_tags
TestTag.respond_to?(:global_all_tags)
#=> true

## Global collection contains the tag
global_tags = TestTag.global_all_tags
global_tags.member?(@tag.identifier)
#=> true

# =============================================
# 11. Validation and Error Handling
# =============================================

## Relationship validation works
TestDomain.validate_relationships!
#=> true

## Individual object validation works
@domain.validate_relationships!
#=> true

## RelationshipError class exists
Familia::Features::Relationships::RelationshipError.ancestors.include?(StandardError)
#=> true

# =============================================
# 12. Performance and Efficiency Features
# =============================================

## Temporary keys are created with TTL
temp_key = @domain.create_temp_key("test_operation", 60)
temp_key.start_with?("temp:")
#=> true

## Batch operations are available
@domain.respond_to?(:batch_zadd)
#=> true

## Score range queries work with permissions
range = @domain.score_range(Time.now - 3600, Time.now, min_permission: :read)
range.is_a?(Array) && range.length == 2
#=> true

# Cleanup
@customer.destroy! if @customer&.exists?
@team.destroy! if @team&.exists?
@domain.destroy! if @domain&.exists?
@tag.destroy! if @tag&.exists?

# Clear any remaining test data
[@customer, @team].each do |owner|
  next unless owner
  owner.domains.clear rescue nil
end

TestDomain.global_all_domains.clear rescue nil
TestTag.global_all_tags.clear rescue nil
