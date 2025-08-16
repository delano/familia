#!/usr/bin/env ruby

require_relative 'try/helpers/test_helpers'

# Create the exact same classes as in the test
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

# Create test objects like in the test
@customer = TestCustomer.new(custid: 'test_cust_123', name: 'Test Customer')
@domain = TestDomain.new(
  domain_id: 'dom_789',
  display_domain: 'example.com',
  created_at: Time.now.to_i,
  permission_level: :write
)

puts "=== Domain Methods Check ==="
puts "@domain.respond_to?(:in_testcustomer_domains?): #{@domain.respond_to?(:in_testcustomer_domains?)}"
puts "@domain.respond_to?(:add_to_testcustomer_domains): #{@domain.respond_to?(:add_to_testcustomer_domains)}"

puts "\nTestDomain instance methods with 'customer':"
puts TestDomain.instance_methods(false).grep(/customer/)

puts "\nTestCustomer instance methods with 'domain':"
puts TestCustomer.instance_methods(false).grep(/domain/)

puts "\nTestDomain tracking relationships:"
puts TestDomain.tracking_relationships.inspect if TestDomain.respond_to?(:tracking_relationships)
