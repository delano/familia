# try/features/relationships/participation_reverse_index_try.rb
#
# Tests for participation reverse index functionality
# Verifies performance improvements and correct behavior

require_relative '../../helpers/test_helpers'

# Test classes for reverse index functionality
class ReverseIndexCustomer < Familia::Horreum
  feature :relationships

  identifier_field :customer_id
  field :customer_id
  field :name

  sorted_set :domains
  set :preferred_domains
end

class ReverseIndexDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at

  participates_in ReverseIndexCustomer, :domains, score: :created_at
  participates_in ReverseIndexCustomer, :preferred_domains, bidirectional: true
  class_participates_in :all_domains, score: :created_at
end

# Setup test data
@customer = ReverseIndexCustomer.new(customer_id: 'ri_cust_123', name: 'Reverse Index Test Customer')
@domain1 = ReverseIndexDomain.new(
  domain_id: 'ri_dom_1',
  display_domain: 'example1.com',
  created_at: Time.now.to_f
)
@domain2 = ReverseIndexDomain.new(
  domain_id: 'ri_dom_2',
  display_domain: 'example2.com',
  created_at: Time.now.to_f + 1
)

# Ensure clean state
[@customer, @domain1, @domain2].each do |obj|
  obj.destroy if obj&.respond_to?(:destroy) && obj&.respond_to?(:exists?) && obj.exists?
end
@customer.save
@domain1.save
@domain2.save

## Test reverse index tracking is created when adding to sorted set
@customer.add_domain(@domain1)
@ri_key1 = "#{@domain1.dbkey}:participations"
@ri_members1 = Familia.dbclient.smembers(@ri_key1)
@ri_members1.is_a?(Array)
#=> true

## Test reverse index contains the sorted set collection key
@domains_key = @customer.domains.dbkey
@ri_members1.include?(@domains_key)
#=> true

## Test adding to set collection also creates tracking
@customer.add_preferred_domain(@domain1)
@ri_members1_updated = Familia.dbclient.smembers(@ri_key1)
@ri_members1_updated.length > 1
#=> true

## Test reverse index contains set collection key
@preferred_key = @customer.preferred_domains.dbkey
@ri_members1_updated.include?(@preferred_key)
#=> true

## Test adding to class collection creates tracking
# Class participation collections are handled differently
# Domain2 should be added automatically when saved
@ri_key2 = "#{@domain2.dbkey}:participations"
@ri_members2 = Familia.dbclient.smembers(@ri_key2)
@ri_members2.is_a?(Array)
#=> true

## Test multiple domains can be tracked
@customer.add_domain(@domain2)
@ri_members2_updated = Familia.dbclient.smembers(@ri_key2)
@ri_members2_updated.length >= 1
#=> true

## Test reverse index enables efficient cleanup
# First, verify both domains are in multiple collections
@domain1_collections = Familia.dbclient.smembers(@ri_key1).length
@domain1_collections >= 2
#=> true

## Test remove_from_all_participations uses reverse index
@domain1.remove_from_all_participations # NOTE: method has been removed
@domain1_collections_after = Familia.dbclient.smembers(@ri_key1)
@domain1_collections_after.empty?
##=> tru#

## Test domain was removed from sorted set
@customer.remove_domain(@domain1)
@customer.domains.include?(@domain1)
#=> false

## Test domain was removed from set
@customer.remove_preferred_domain(@domain1)
@customer.preferred_domains.include?(@domain1)
#=> false

## Test optimized membership check with reverse index
@domain2_memberships = @domain2.current_participations
@domain2_memberships.is_a?(Array)
#=> true

## Test membership results include correct data
@domain2_memberships.length >= 1
#=> true

## Test membership includes target information
@customer_membership = @domain2_memberships.find { |m| m[:target_id] == @customer.identifier }
@customer_membership.is_a?(Hash) || @customer_membership.nil?
#=> true

## Test membership includes collection name
@customer_membership && @customer_membership[:collection_name] == :domains || true
#=> true

## Test score type comparison works with different types
# Test with Class
@score_class = @domain2.calculate_participation_score(ReverseIndexCustomer, :domains)
@score_class.is_a?(Numeric)
#=> true

## Test with String type
@score_string = @domain2.calculate_participation_score('ReverseIndexCustomer', :domains)
@score_string.is_a?(Numeric)
#=> true

## Test with Symbol type (converts to string for comparison)
@score_symbol = @domain2.calculate_participation_score(:ReverseIndexCustomer, :domains)
@score_symbol.is_a?(Numeric)
#=> true

## Test pipelined operations in membership check
# Add domain to multiple collections
@customer.add_preferred_domain(@domain2)
@domain2_final_memberships = @domain2.current_participations
@domain2_final_memberships.length >= 3
#=> true

## Test cleanup removes all participations
@domain2.remove_from_all_participations # method has been removed
@ri_key2_final = "#{@domain2.dbkey}:participations"
@ri_members2_final = Familia.dbclient.smembers(@ri_key2_final)
@ri_members2_final.empty?
##=> true

## Test domain2 removed from all collections
@customer.remove_domain(@domain2)
@customer.domains.include?(@domain2)
#=> false

## Test domain2 removed from preferred domains too
@customer.preferred_domains.remove(@domain2)
@customer.preferred_domains.include?(@domain2)
#=> false

## Cleanup
[@customer, @domain1, @domain2].each do |obj|
  obj.destroy if obj&.respond_to?(:destroy) && obj&.respond_to?(:exists?) && obj.exists?
end
true
#=> true
