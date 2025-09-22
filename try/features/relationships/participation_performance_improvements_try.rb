# try/features/relationships/participation_performance_improvements_try.rb
#
# Tests for performance improvements in participation functionality
# Verifies reverse index functionality and robust type comparison

require_relative '../../helpers/test_helpers'

# Test classes for performance improvements
class PerfTestCustomer < Familia::Horreum
  feature :relationships

  identifier_field :customer_id
  field :customer_id
  field :name

  sorted_set :domains
end

class PerfTestDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at

  participates_in PerfTestCustomer, :domains, score: :created_at
end

# Setup test data
@customer = PerfTestCustomer.new(customer_id: 'perf_cust_123', name: 'Performance Test Customer')
@domain = PerfTestDomain.new(
  domain_id: 'perf_dom_1',
  display_domain: 'perf-example.com',
  created_at: Time.now.to_f
)

# Ensure clean state
[@customer, @domain].each do |obj|
  obj.destroy if obj&.respond_to?(:destroy) && obj&.respond_to?(:exists?) && obj.exists?
end
@customer.save
@domain.save

## Test reverse index tracking methods exist
@domain.respond_to?(:add_participation_tracking)
#=> true

## Test reverse index removal methods exist
@domain.respond_to?(:remove_participation_tracking)
#=> true

## Test add domain creates reverse index tracking
@customer.add_domain(@domain)
@reverse_index_key = "#{@domain.dbkey}:participations"
@tracked_collections = Familia.dbclient.smembers(@reverse_index_key)
@tracked_collections.length > 0
#=> true

## Test reverse index contains correct collection key
@collection_key = @customer.domains.dbkey
@tracked_collections.include?(@collection_key)
#=> true

## Test remove domain cleans up reverse index tracking
@customer.remove_domain(@domain)
@tracked_collections_after_remove = Familia.dbclient.smembers(@reverse_index_key)
@tracked_collections_after_remove.include?(@collection_key)
#=> false

## Test robust type comparison in score calculation works with Class
@customer.add_domain(@domain)
@score_with_class = @domain.calculate_participation_score(PerfTestCustomer, :domains)
@score_with_class.is_a?(Numeric)
#=> true

## Test robust type comparison works with String
@score_with_string = @domain.calculate_participation_score('PerfTestCustomer', :domains)
@score_with_string.is_a?(Numeric)
#=> true

## Test participation collections membership method works
@memberships = @domain.participation_collections_membership
@memberships.is_a?(Array)
#=> true

## Test membership data structure is correct
@memberships.length > 0
#=> true

## Test membership contains expected target class
@membership = @memberships.first
@membership[:target_class] == 'PerfTestCustomer'
#=> true

## Test membership contains collection name
@membership[:collection_name] == :domains
#=> true

## Test membership contains type information
@membership[:type] == :sorted_set
#=> true

## Test remove from all participation collections works efficiently
@domain.remove_from_all_participation_collections
@final_tracked_collections = Familia.dbclient.smembers(@reverse_index_key)
@final_tracked_collections.empty?
#=> true

## Test domain is removed from customer collection
@customer.domains.include?(@domain.identifier)
#=> false

## Cleanup
[@customer, @domain].each do |obj|
  obj.destroy if obj&.respond_to?(:destroy) && obj&.respond_to?(:exists?) && obj.exists?
end
true
#=> true
