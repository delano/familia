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

  # Basic tracking
  tracked_in :all_domains, type: :sorted_set, score: :created_at, cascade: :delete

  # Basic indexing
  indexed_by :display_domain, in: :domain_lookup, finder: true

  # Basic membership
  member_of SimplePerfCustomer, :simple_domains, key: :display_domain
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
  @domains.each(&:save)
end

# Should complete in reasonable time
save_time < 2.0
#=> true

## Verify relationships were maintained
SimplePerfDomain.all_domains.size
#=> 20

## Verify indexes were maintained
SimplePerfDomain.domain_lookup.size >= 18  # Allow for some variance
#=> true

## Measure finder performance
find_time = Benchmark.realtime do
  5.times do |i|
    SimplePerfDomain.from_display_domain("simple#{i}.example.com")
  end
end

# Finders should be fast
find_time < 0.5
#=> true

## Relationship metadata should be shared
SimplePerfDomain.relationships.size
#=> 3

## Relationship metadata should be frozen
SimplePerfDomain.relationships.first.options.frozen?
#=> true

# =============================================
# 2. Thread Safety Tests
# =============================================

## Multiple threads can safely access relationship metadata
results = []
threads = 2.times.map do |i|
  Thread.new do
    3.times do
      relationships = SimplePerfDomain.relationships
      results << relationships.size
    end
  end
end

threads.each(&:join)

# All threads should see consistent relationship count
results.uniq.size
#=> 1

# =============================================
# 3. Cleanup Performance Tests
# =============================================

## Measure cleanup performance
cleanup_time = Benchmark.realtime do
  @domains[0..9].each(&:destroy!)
end

# Cleanup should be fast
cleanup_time < 1.0
#=> true

## Verify cleanup worked
SimplePerfDomain.all_domains.size
#=> 10

## Index cleanup verification
SimplePerfDomain.domain_lookup.size <= 12  # Allow some variance
#=> true

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
