# try/features/relationships/participation_target_class_resolution_try.rb
#
# Regression test for Symbol/String target class resolution in participates_in
#
# This test verifies the fix for the NoMethodError that occurred when
# participates_in was called with a Symbol or String target class instead
# of a Class object. The error was:
#   "private method 'member_by_config_name' called for module Familia"
#
# See commit: Fix NoMethodError when calling private member_by_config_name

require_relative '../../support/helpers/test_helpers'

# Test classes for target class resolution
# Define target class FIRST so it's registered in Familia.members
class SymbolResolutionCustomer < Familia::Horreum
  feature :relationships

  identifier_field :customer_id
  field :customer_id
  field :name

  sorted_set :domains
  set :tags
end

# Participant classes using different target class formats
class SymbolResolutionDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :name
  field :created_at

  # TEST CASE 1: Symbol target class (most common case)
  # This was causing: NoMethodError: private method 'member_by_config_name'
  participates_in :SymbolResolutionCustomer, :domains, score: :created_at
end

class StringResolutionTag < Familia::Horreum
  feature :relationships

  identifier_field :tag_id
  field :tag_id
  field :name
  field :created_at

  # TEST CASE 2: String target class
  # This was also causing the same NoMethodError
  participates_in 'SymbolResolutionCustomer', :tags, score: :created_at
end

class ClassResolutionItem < Familia::Horreum
  feature :relationships

  identifier_field :item_id
  field :item_id
  field :name
  field :created_at

  # TEST CASE 3: Class object (this always worked)
  # Including for completeness
  sorted_set :items
end

# Setup test data
@customer = SymbolResolutionCustomer.new(
  customer_id: 'symbol_res_cust_1',
  name: 'Symbol Resolution Customer'
)
@domain = SymbolResolutionDomain.new(
  domain_id: 'symbol_res_dom_1',
  name: 'example.com',
  created_at: Time.now.to_f
)
@tag = StringResolutionTag.new(
  tag_id: 'string_res_tag_1',
  name: 'important',
  created_at: Time.now.to_f
)

# Ensure clean state
[@customer, @domain, @tag].each do |obj|
  obj.destroy if obj&.respond_to?(:destroy) && obj&.respond_to?(:exists?) && obj.exists?
end

@customer.save
@domain.save
@tag.save

## Test Symbol target class resolution works
# This is the primary regression test - it should not raise NoMethodError
@customer.add_domain(@domain)
@customer.domains.member?(@domain.identifier)
#=> true

## Test domain bidirectional methods were created correctly
@domain.respond_to?(:in_symbol_resolution_customer_domains?)
#=> true

## Test domain can check membership using generated method
@domain.in_symbol_resolution_customer_domains?(@customer)
#=> true

## Test domain can add itself using generated method
@customer.domains.remove(@domain)
@domain.add_to_symbol_resolution_customer_domains(@customer)
@customer.domains.member?(@domain.identifier)
#=> true

## Test domain score calculation works with Symbol target class
@score = @domain.calculate_participation_score(:SymbolResolutionCustomer, :domains)
@score.is_a?(Numeric)
#=> true

## Test domain score matches created_at field
(@score - @domain.created_at).abs < 0.001
#=> true

## Test String target class resolution works
# This is the secondary regression test
@customer.add_tag(@tag)
@customer.tags.member?(@tag.identifier)
#=> true

## Test tag bidirectional methods were created correctly
@tag.respond_to?(:in_symbol_resolution_customer_tags?)
#=> true

## Test tag can check membership using generated method
@tag.in_symbol_resolution_customer_tags?(@customer)
#=> true

## Test tag can add itself using generated method
@customer.tags.remove(@tag)
@tag.add_to_symbol_resolution_customer_tags(@customer)
@customer.tags.member?(@tag.identifier)
#=> true

## Test tag score calculation works with String target class
@tag_score = @tag.calculate_participation_score('SymbolResolutionCustomer', :tags)
@tag_score.is_a?(Numeric)
#=> true

## Test reverse index tracking works with Symbol target class
@domain.participations.members.length > 0
#=> true

## Test reverse index contains the correct collection key
@domains_key = @customer.domains.dbkey
@domain.participations.members.include?(@domains_key)
#=> true

## Test reverse index tracking works with String target class
@tag.participations.members.length > 0
#=> true

## Test reverse index contains the correct collection key for tags
@tags_key = @customer.tags.dbkey
@tag.participations.members.include?(@tags_key)
#=> true

## Test current_participations works with Symbol target class
@domain_participations = @domain.current_participations
@domain_participations.is_a?(Array)
#=> true

## Test participation data includes correct target class
@domain_participation = @domain_participations.first
@domain_participation[:target_class] == 'SymbolResolutionCustomer'
#=> true

## Test current_participations works with String target class
@tag_participations = @tag.current_participations
@tag_participations.is_a?(Array)
#=> true

## Test participation data includes correct collection name
@tag_participation = @tag_participations.first
@tag_participation[:collection_name] == :tags
#=> true

## Test removal works correctly with Symbol target class
@customer.remove_domain(@domain)
@customer.domains.member?(@domain.identifier)
#=> false

## Test reverse index cleanup with Symbol target class
@domain.participations.members.empty?
#=> true

## Test removal works correctly with String target class
@customer.remove_tag(@tag)
@customer.tags.member?(@tag.identifier)
#=> false

## Test reverse index cleanup with String target class
@tag.participations.members.empty?
#=> true

## Cleanup
[@customer, @domain, @tag].each do |obj|
  obj.destroy if obj&.respond_to?(:destroy) && obj&.respond_to?(:exists?) && obj.exists?
end
true
#=> true
