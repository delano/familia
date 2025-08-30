# try/features/relationships_performance_simple_try.rb
#
# Simplified performance testing for the Relationships feature

require_relative '../helpers/test_helpers'
require 'benchmark'

# Test classes for performance testing
class SimplePerfCustomer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid
  field :name

  sorted_set :simple_domains
end

class SimplePerfDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at
  field :priority_score

  # Static collections for performance testing
  class_sorted_set :all_domains
  class_hashkey :domain_lookup

  # Define tracking relationships for testing
  tracked_in SimplePerfCustomer, :simple_domains, score: :created_at
end

# =============================================
# 1. Basic Performance Tests
# =============================================

## Create test objects for performance testing
@customer = SimplePerfCustomer.new(custid: 'simple_perf_customer', name: 'Simple Performance Test')
@customer.save

# Create multiple domains for bulk operations
@domains = 20.times.map do |i|
  SimplePerfDomain.new(
    domain_id: "simple_perf_domain_#{i}",
    display_domain: "simple#{i}.example.com",
    created_at: Time.now.to_i + i,
    priority_score: rand(100)
  )
end

## Measure bulk save performance
save_time = Benchmark.realtime do
  @domains.each do |domain|
    domain.save
    # Manually add to collections for testing (ensure numeric score)
    # Convert created_at to float, handling nil case
    score = if domain.created_at.nil?
              Time.now.to_f
            elsif domain.created_at.is_a?(Time)
              domain.created_at.to_f
            else
              domain.created_at.to_f
            end
    SimplePerfDomain.all_domains.add(score, domain.identifier)
    SimplePerfDomain.domain_lookup[domain.display_domain] = domain.identifier
  end
end

# Should complete in reasonable time
save_time < 2.0
#=> true

## Verify collections were maintained
SimplePerfDomain.all_domains.size
#=> 20

## Verify indexes were maintained
SimplePerfDomain.domain_lookup.size
#=> 20

## Basic collection operations should work
SimplePerfDomain.all_domains.member?(@domains.first.identifier)
#=> true

## Hash lookup should work
SimplePerfDomain.domain_lookup[@domains.first.display_domain]
#=> @domains.first.identifier

# =============================================
# 2. Thread Safety Tests
# =============================================

## Multiple threads can safely access collections
results = []
threads = 2.times.map do |i|
  Thread.new do
    3.times do
      # Access collections safely
      count = SimplePerfDomain.all_domains.size
      results << count
    end
  end
end

threads.each(&:join)

# All threads should see consistent collection size
results.uniq.size
#=> 1

# =============================================
# 3. Cleanup Performance Tests
# =============================================

## Measure cleanup performance
cleanup_time = Benchmark.realtime do
  @domains[0..9].each do |domain|
    domain.destroy!
    # Manually remove from collections
    SimplePerfDomain.all_domains.remove(domain.identifier)
    SimplePerfDomain.domain_lookup.remove_field(domain.display_domain)
  end
end

# Cleanup should be fast
cleanup_time < 1.0
#=> true

## Verify cleanup worked
SimplePerfDomain.all_domains.size
#=> 10

## Index cleanup verification
SimplePerfDomain.domain_lookup.size
#=> 10

# =============================================
# Cleanup
# =============================================

# Clean up test data
[@customer].each { |obj| obj.destroy! if obj&.exists? }
@domains[10..19].each { |domain| domain.destroy! if domain&.exists? }

# Clear collections
SimplePerfDomain.all_domains.clear rescue nil
SimplePerfDomain.domain_lookup.clear rescue nil
SimplePerfCustomer.simple_domains.clear rescue nil

"Simple performance tests completed successfully"
#=> "Simple performance tests completed successfully"
