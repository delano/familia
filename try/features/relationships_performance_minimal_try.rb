# Minimal performance testing focusing on core Familia functionality

require_relative '../helpers/test_helpers'
require 'benchmark'

# Simple test classes without relationships feature
class MinimalCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
end

class MinimalDomain < Familia::Horreum
  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :priority_score

  # Direct collections without relationships
  class_sorted_set :all_domains
  class_set :active_domains
  class_list :domain_history
  class_hashkey :domain_lookup
end

# Basic performance tests

## Create test objects
@customer = MinimalCustomer.new(custid: 'minimal_customer', name: 'Minimal Test')
@customer.save

@domains = 20.times.map do |i|
  MinimalDomain.new(
    domain_id: "minimal_domain_#{i}",
    display_domain: "minimal#{i}.example.com",
    priority_score: i * 10
  )
end
@customer.nil?
#=> false

## Measure bulk save performance
save_time = Benchmark.realtime do
  @domains.each do |domain|
    domain.save
    # Use numeric scores for sorted sets
    MinimalDomain.all_domains.add(domain.priority_score.to_f, domain.identifier)
    MinimalDomain.active_domains.add(domain.identifier)
    MinimalDomain.domain_history.push(domain.identifier)
    MinimalDomain.domain_lookup[domain.display_domain] = domain.identifier
  end
end

save_time&.to_f < 2.0 # Should complete quickly
#=> true

## Verify collections work
MinimalDomain.all_domains.size
#=> 20

## Verify hash works
MinimalDomain.domain_lookup.size
#=> 20

## Test membership
MinimalDomain.all_domains.member?(@domains.first.identifier)
#=> true

## Test hash lookup
MinimalDomain.domain_lookup[@domains.first.display_domain]
#=> @domains.first.identifier

## Test sorted set scoring
score = MinimalDomain.all_domains.score(@domains.first.identifier)
score == @domains.first.priority_score.to_f
#=> true

## Test removal from collections
cleanup_time = Benchmark.realtime do
  @domains[0..9].each do |domain|
    domain.destroy!
    MinimalDomain.all_domains.remove(domain.identifier)
    MinimalDomain.active_domains.remove(domain.identifier)
    MinimalDomain.domain_lookup.remove_field(domain.display_domain)
  end
end

# Cleanup should be fast
cleanup_time < 1.0
#=> true

## Verify cleanup worked
MinimalDomain.all_domains.size
#=> 10

## Verify hash cleanup
MinimalDomain.domain_lookup.size
#=> 10

## Test with larger dataset
@large_domains = 100.times.map do |i|
  MinimalDomain.new(domain_id: "large_#{i}", priority_score: i)
end

large_time = Benchmark.realtime do
  @large_domains.each do |domain|
    domain.save
    MinimalDomain.all_domains.add(domain.priority_score.to_f, domain.identifier)
  end
end

# Should handle larger datasets
large_time&.to_f < 5.0
#=> true

## Verify large dataset
MinimalDomain.all_domains.size >= 110  # 10 remaining + 100 new
#=> true

## Clean up all test data
[@customer].each { |obj| obj.destroy! if obj&.exists? }
@domains[10..19].each { |domain| domain.destroy! if domain&.exists? }
@large_domains.each { |domain| domain.destroy! if domain&.exists? }

# Clear collections
MinimalDomain.all_domains.clear rescue nil
MinimalDomain.active_domains.clear rescue nil
MinimalDomain.domain_history.clear rescue nil
MinimalDomain.domain_lookup.clear rescue nil

"Minimal performance tests completed successfully"
#=> "Minimal performance tests completed successfully"
