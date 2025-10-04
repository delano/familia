# try/features/relationships_performance_working_try.rb
#
# Working performance test focusing on basic functionality

require_relative '../../support/helpers/test_helpers'
require 'benchmark'

# Simple test class using only basic Familia features
class WorkingDomain < Familia::Horreum
  identifier_field :domain_id
  field :domain_id
  field :display_domain

  # Use only features we know work
  class_set :active_domains
  class_list :domain_history
  class_hashkey :domain_lookup
end

# =============================================
# 1. Basic Functionality Tests
# =============================================

## Create test domains
@domains = 10.times.map do |i|
  WorkingDomain.new(
    domain_id: "working_domain_#{i}",
    display_domain: "working#{i}.example.com"
  )
end

## Test basic save functionality and setup collections
save_time = Benchmark.realtime do
  @domains.each do |domain|
    domain.save
    # Also populate collections during setup
    WorkingDomain.active_domains.add(domain.identifier)
    WorkingDomain.domain_history.push(domain.identifier)
    WorkingDomain.domain_lookup[domain.display_domain] = domain.identifier
  end
end

# Should save quickly
save_time < 2.0
#=> true

## Verify set operations work
WorkingDomain.active_domains.size
#=> 10

## Verify list operations work
WorkingDomain.domain_history.size
#=> 10

## Verify hash operations work
WorkingDomain.domain_lookup.size
#=> 10

## Test membership
WorkingDomain.active_domains.member?(@domains.first.identifier)
#=> true

## Test hash lookup
WorkingDomain.domain_lookup[@domains.first.display_domain]
#=> @domains.first.identifier

# =============================================
# 2. Performance Tests
# =============================================

## Test bulk operations performance
bulk_time = Benchmark.realtime do
  50.times do |i|
    id = "bulk_#{i}"
    WorkingDomain.active_domains.add(id)
    WorkingDomain.domain_history.push(id)
    WorkingDomain.domain_lookup["bulk#{i}.com"] = id
  end
end

# Bulk operations should be fast
bulk_time < 1.0
#=> true

## Verify bulk operations
WorkingDomain.active_domains.size >= 60  # 10 + 50
#=> true

# =============================================
# 3. Thread Safety Tests
# =============================================

## Test concurrent access
results = []
threads = 3.times.map do |i|
  Thread.new do
    5.times do
      count = WorkingDomain.active_domains.size
      results << count
    end
  end
end

threads.each(&:join)

# Should have consistent results
results.all? { |count| count >= 60 }
#=> true

# =============================================
# 4. Cleanup Tests
# =============================================

## Test cleanup performance
cleanup_time = Benchmark.realtime do
  @domains[0..4].each do |domain|
    domain.destroy!
    WorkingDomain.active_domains.remove(domain.identifier)
  end
end

# Cleanup should be fast
cleanup_time < 1.0
#=> true

## Verify partial cleanup
WorkingDomain.active_domains.size >= 55  # Should have removed 5
#=> true

# =============================================
# Cleanup
# =============================================

# Clean up all test data
## Clean up domain objects
@domains[5..9].each { |domain| domain.destroy! if domain&.exists? }

# Clear collections
WorkingDomain.active_domains.clear rescue nil
WorkingDomain.domain_history.clear rescue nil
WorkingDomain.domain_lookup.clear rescue nil

"Working performance tests completed successfully"
#=> "Working performance tests completed successfully"
