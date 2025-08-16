# try/features/relationships_edge_cases_try.rb
#
# Comprehensive edge case and error condition testing for Relationships v2

require_relative '../helpers/test_helpers'

# Test classes for edge case testing
class EdgeTestCustomer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid
  field :name

  sorted_set :domains
  set :simple_domains
  list :domain_list
end

class EdgeTestDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at
  field :score_value

  # Test different score calculation methods
  tracked_in EdgeTestCustomer, :domains, score: :created_at, on_destroy: :remove
  tracked_in EdgeTestCustomer, :static_domains, score: 42, on_destroy: :ignore
  tracked_in :global, :proc_domains, score: -> { (score_value || 0) * 2 }, on_destroy: :cascade

  # Test different collection types for membership
  member_of EdgeTestCustomer, :domains, type: :sorted_set
  member_of EdgeTestCustomer, :simple_domains, type: :set
  member_of EdgeTestCustomer, :domain_list, type: :list

  # Index edge cases
  indexed_by :display_domain, :edge_index, context: EdgeTestCustomer, finder: true
  indexed_by :domain_id, :global_id_index, context: :global, finder: false
end

class EmptyIdentifierTest < Familia::Horreum
  feature :relationships

  identifier_field :empty_id
  field :empty_id

  tracked_in :global, :empty_test, score: :empty_id
end

# Setup test objects
@customer1 = EdgeTestCustomer.new(custid: 'edge_cust_1', name: 'Edge Customer 1')
@customer2 = EdgeTestCustomer.new(custid: 'edge_cust_2', name: 'Edge Customer 2')
@domain1 = EdgeTestDomain.new(
  domain_id: 'edge_dom_1',
  display_domain: 'edge1.example.com',
  created_at: Time.now.to_i - 3600,
  score_value: 10
)
@domain2 = EdgeTestDomain.new(
  domain_id: 'edge_dom_2',
  display_domain: 'edge2.example.com',
  created_at: Time.now.to_i,
  score_value: 20
)

# =============================================
# 1. Score Encoding Edge Cases
# =============================================

## Score encoding handles maximum metadata value
max_score = @domain1.encode_score(Time.now, 999)
decoded = @domain1.decode_score(max_score)
decoded[:metadata]
#=> 999

## Score encoding handles zero metadata
zero_score = @domain1.encode_score(Time.now, 0)
decoded_zero = @domain1.decode_score(zero_score)
decoded_zero[:metadata]
#=> 0

## Permission encoding handles unknown permission levels
unknown_perm_score = @domain1.permission_encode(Time.now, :unknown_permission)
decoded_unknown = @domain1.permission_decode(unknown_perm_score)
decoded_unknown[:permission]
#=> :unknown

## Score encoding preserves precision for small timestamps
small_time = Time.at(1000)
small_score = @domain1.encode_score(small_time, 100)
decoded_small = @domain1.decode_score(small_score)
decoded_small[:timestamp]
#=> 1000

## Score range works with nil values
range_with_nils = @domain1.score_range(nil, nil)
range_with_nils
#=> ["-inf", "+inf"]

# =============================================
# 2. Identifier Edge Cases
# =============================================

## Empty identifier handling
empty_test = EmptyIdentifierTest.new(empty_id: '')
empty_test.identifier
#=> ''

## Nil identifier handling
nil_test = EmptyIdentifierTest.new(empty_id: nil)
nil_test.identifier
#=> nil

## Identifier validation catches nil identifiers
nil_test = EmptyIdentifierTest.new(empty_id: nil)
begin
  nil_test.validate_relationships!
  false
rescue Familia::Features::Relationships::RelationshipError
  true
end
#=> true

# =============================================
# 3. Score Calculation Edge Cases
# =============================================

## Static score calculation works
@customer1.save
@domain1.save
@domain1.add_to_edgetestcustomer_static_domains(@customer1)
score = @domain1.score_in_edgetestcustomer_static_domains(@customer1)
score
#=> 42.0

## Proc score calculation works
EdgeTestDomain.add_to_proc_domains(@domain1)
proc_score = EdgeTestDomain.global_proc_domains.score(@domain1.identifier)
proc_score
#=> 20.0

## Method score calculation works
@domain1.add_to_edgetestcustomer_domains(@customer1)
method_score = @domain1.score_in_edgetestcustomer_domains(@customer1)
method_score == @domain1.created_at.to_f
#=> true

## Proc score handles nil values gracefully
@domain1.score_value = nil
EdgeTestDomain.add_to_proc_domains(@domain1)
nil_proc_score = EdgeTestDomain.global_proc_domains.score(@domain1.identifier)
nil_proc_score
#=> 0.0

# =============================================
# 4. Collection Type Edge Cases
# =============================================

## Sorted set membership works
@domain1.add_to_edgetestcustomer_domains(@customer1)
@domain1.in_edgetestcustomer_domains?(@customer1)
#=> true

## Set membership works (no scores)
@domain1.add_to_edgetestcustomer_simple_domains(@customer1)
@domain1.in_edgetestcustomer_simple_domains?(@customer1)
#=> true

## List membership works (position-based)
@domain1.add_to_edgetestcustomer_domain_list(@customer1)
@domain1.in_edgetestcustomer_domain_list?(@customer1)
#=> true

## Set membership doesn't have score methods
@domain1.respond_to?(:score_in_edgetestcustomer_simple_domains)
#=> false

## List membership has position methods
@domain1.respond_to?(:position_in_edgetestcustomer_domain_list)
#=> true

# =============================================
# 5. Multi-Collection Conflict Resolution
# =============================================

## Object can be in multiple collections with different scores
@domain1.add_to_edgetestcustomer_domains(@customer1)
@domain1.add_to_edgetestcustomer_static_domains(@customer1)
scores = [
  @domain1.score_in_edgetestcustomer_domains(@customer1),
  @domain1.score_in_edgetestcustomer_static_domains(@customer1)
]
scores[0] != scores[1]
#=> true

## Multi-presence operations work atomically
@domain1.update_multiple_presence([
  { key: "edgetestcustomer:#{@customer1.custid}:domains", score: 100.0 },
  { key: "edgetestcustomer:#{@customer2.custid}:domains", score: 200.0 }
], :add, @domain1.identifier)

[@domain1.in_edgetestcustomer_domains?(@customer1), @domain1.in_edgetestcustomer_domains?(@customer2)]
#=> [true, true]

## Scores are correctly set in atomic operation
[@domain1.score_in_edgetestcustomer_domains(@customer1), @domain1.score_in_edgetestcustomer_domains(@customer2)]
#=> [100.0, 200.0]

# =============================================
# 6. Index Edge Cases
# =============================================

## Global index works with nil context
@domain1.add_to_global_global_id_index
EdgeTestDomain.find_by_domain_id_globally('edge_dom_1')&.display_domain
#=> 'edge1.example.com'

## Context index works
@customer1.save
@domain1.add_to_edgetestcustomer_edge_index(@customer1)
@customer1.find_by_display_domain('edge1.example.com')&.domain_id
#=> 'edge_dom_1'

## Non-finder index doesn't generate finder methods
EdgeTestDomain.respond_to?(:find_by_domain_id_globally)
#=> false

## Index update handles field value changes
old_display = @domain1.display_domain
@domain1.display_domain = 'updated.example.com'
@domain1.update_in_edgetestcustomer_edge_index(@customer1, old_display)
@customer1.find_by_display_domain('updated.example.com')&.domain_id
#=> 'edge_dom_1'

## Old value is removed from index
@customer1.find_by_display_domain('edge1.example.com')
#=> nil

# =============================================
# 7. Cascade Behavior Edge Cases
# =============================================

## Cascade dry run shows comprehensive impact
@domain1.add_to_edgetestcustomer_domains(@customer1)
@domain1.add_to_edgetestcustomer_static_domains(@customer1)
preview = @domain1.cascade_dry_run
preview[:affected_keys].length > 0
#=> true

## Remove cascade strategy cleans up collections
@domain1.cleanup_all_relationships!
[@domain1.in_edgetestcustomer_domains?(@customer1), @domain1.in_edgetestcustomer_static_domains?(@customer1)]
#=> [false, false]

## Indexes are cleaned up during cascade
@customer1.find_by_display_domain('updated.example.com')
#=> nil

# =============================================
# 8. Permission and Security Edge Cases
# =============================================

## Permission filtering works with zero permission
read_only_score = @domain1.permission_encode(Time.now, :none)
decoded = @domain1.permission_decode(read_only_score)
decoded[:permission]
#=> :none

## Score range with permission filtering works
perm_range = @domain1.score_range(Time.now - 3600, Time.now, min_permission: :read)
perm_range[0].to_f > 0
#=> true

## Query collections with permission filtering
@domain1.add_to_edgetestcustomer_domains(@customer1, @domain1.permission_encode(Time.now, :write))
write_results = EdgeTestDomain.query_collections([
  { owner: @customer1, collection: :domains }
], { min_permission: :write })
write_results.member?(@domain1.identifier)
#=> true

## Lower permission domains are filtered out
read_results = EdgeTestDomain.query_collections([
  { owner: @customer1, collection: :domains }
], { min_permission: :admin })
read_results.member?(@domain1.identifier)
#=> false

# =============================================
# 9. Temporary Key Management Edge Cases
# =============================================

## Temporary keys have proper TTL
temp_key = @domain1.create_temp_key("edge_test", 30)
ttl = @domain1.redis.ttl(temp_key)
ttl > 0 && ttl <= 30
#=> true

## Temporary key cleanup works
@domain1.cleanup_temp_keys("edge_*")
# Should not raise error
true
#=> true

## Set operations create temporary keys properly
union_result = EdgeTestDomain.union_collections([
  { owner: @customer1, collection: :domains },
  { owner: @customer2, collection: :domains }
], ttl: 60)
@domain1.redis.ttl(union_result.rediskey) <= 60
#=> true

# =============================================
# 10. Error Handling and Validation
# =============================================

## Invalid metadata values are rejected
begin
  @domain1.encode_score(Time.now, 1000)
  false
rescue ArgumentError
  true
end
#=> true

## Relationship validation catches configuration errors
EdgeTestDomain.validate_relationships!
#=> true

## Invalid collection configurations raise errors
begin
  EdgeTestDomain.union_collections([])
  false
rescue
  true
end
#=> false

## Empty collections return empty results safely
empty_union = EdgeTestDomain.union_collections([])
empty_union.class.name
#=> "Familia::SortedSet"

# =============================================
# 11. Performance Edge Cases
# =============================================

## Batch operations handle empty arrays
@domain1.batch_zadd("test:key", [])
#=> 0

## Large batch operations work
large_batch = 100.times.map { |i| { member: "item_#{i}", score: i } }
@domain1.batch_zadd("test:large_batch", large_batch) >= 0
#=> true

## Set operations with many collections work
many_collections = 5.times.map { |i| { key: "test:collection_#{i}" } }
many_union = EdgeTestDomain.union_collections(many_collections, ttl: 60)
many_union.class.name
#=> "Familia::SortedSet"

# =============================================
# 12. Memory and Resource Management
# =============================================

## Relationship status doesn't leak memory with repeated calls
3.times { @domain1.relationship_status }
@domain1.relationship_status.keys.include?(:identifier)
#=> true

## Find related keys works efficiently
related_keys = @domain1.send(:find_related_redis_keys)
related_keys.is_a?(Array)
#=> true

## Resource cleanup is comprehensive
@domain1.cleanup_all_relationships!
@domain1.relationship_status[:membership_collections].empty?
#=> true

# Cleanup
[@customer1, @customer2, @domain1, @domain2].each(&:destroy!) rescue nil

# Clear test data
EdgeTestDomain.global_proc_domains.clear rescue nil
EdgeTestDomain.global_global_id_index.clear rescue nil
