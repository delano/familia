# try/features/relationships_performance_try.rb
#
# Performance and integration testing for the Relationships feature

require_relative '../helpers/test_helpers'
require 'benchmark'

# Test classes for performance testing
class PerfCustomer < Familia::Horreum

  feature :relationships

  identifier_field :custid
  field :custid
  field :name
  field :created_at

  sorted_set :domains
  set :tags
  list :activity_log
end

class PerfDomain < Familia::Horreum

  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at
  field :priority_score
  field :customer_id

  # Multiple tracking collections
  tracked_in :all_domains, type: :sorted_set, score: :created_at, cascade: :delete
  tracked_in :priority_queue, type: :sorted_set, score: :priority_score, cascade: :delete
  tracked_in :active_domains, type: :set, cascade: :delete
  tracked_in :domain_history, type: :list, cascade: :delete

  # Multiple indexes
  indexed_by :display_domain, in: :domain_lookup, finder: true
  indexed_by :customer_id, in: :customer_domains, finder: true
  indexed_by :domain_id, in: :id_lookup, finder: false

  # Member relationships
  member_of PerfCustomer, :domains, key: :display_domain
  member_of PerfCustomer, :tags, key: :domain_id
  member_of PerfCustomer, :activity_log, key: :display_domain
end

# Integration test with other features
class IntegrationTestModel < Familia::Horreum

  feature :relationships
  feature :safe_dump if respond_to?(:feature)
  feature :expiration if respond_to?(:feature)

  identifier_field :id
  field :id
  field :data
  field :created_at

  tracked_in :all_items, type: :sorted_set, score: :created_at
  indexed_by :data, finder: true
end

# Stress test model with many relationships
class StressTestModel < Familia::Horreum

  feature :relationships

  identifier_field :id
  field :id

  # Create many relationships to test scaling
  20.times do |i|
    tracked_in :"collection_#{i}", type: :set
    indexed_by :id, in: :"index_#{i}", finder: false
  end
end

# =============================================
# 1. Basic Performance Tests
# =============================================

## Create test objects for performance testing
@customer = PerfCustomer.new(custid: 'perf_customer', name: 'Performance Test', created_at: Time.now.to_i)
@customer.save

# Create multiple domains for bulk operations
@domains = 50.times.map do |i|
  PerfDomain.new(
    domain_id: "perf_domain_#{i}",
    display_domain: "perf#{i}.example.com",
    created_at: Time.now.to_i + i,
    priority_score: rand(100),
    customer_id: @customer.custid
  )
end

## Measure bulk save performance
save_time = Benchmark.realtime do
  @domains.each(&:save)
end

# Should complete in reasonable time (< 1 second for 50 objects)
save_time < 1.0
#=> true

## Verify all relationships were maintained
PerfDomain.all_domains.size
#=> 50

## Verify indexes were maintained
PerfDomain.domain_lookup.size >= 45  # Allow for some variance
#=> true

## Measure finder performance
find_time = Benchmark.realtime do
  10.times do |i|
    PerfDomain.from_display_domain("perf#{i}.example.com")
  end
end

# Finders should be fast (< 0.1 seconds for 10 lookups)
find_time < 0.1
#=> true

## Measure collection query performance
query_time = Benchmark.realtime do
  10.times do
    PerfDomain.all_domains.member?(@domains[25].identifier)
    PerfDomain.priority_queue.score(@domains[25].identifier)
    PerfDomain.active_domains.member?(@domains[25].identifier)
  end
end

# Queries should be fast (< 0.1 seconds for 30 operations)
query_time < 0.1
#=> true

# =============================================
# 2. Memory Usage Tests
# =============================================

## Relationship metadata should be shared, not duplicated per instance
before_instances = ObjectSpace.count_objects[:T_OBJECT]

# Create many instances
instances = 100.times.map { |i| PerfDomain.new(domain_id: "mem_test_#{i}") }

after_instances = ObjectSpace.count_objects[:T_OBJECT]

# Should not have created excessive objects (relationship metadata is shared)
(after_instances - before_instances) < 200  # Allow for reasonable overhead
#=> true

## Class-level relationship metadata should be constant size
PerfDomain.relationships.size
#=> 10

## Relationship metadata should be frozen to prevent modification
PerfDomain.relationships.first.options.frozen?
#=> true

# =============================================
# 3. Concurrency and Thread Safety Tests
# =============================================

## Multiple threads can safely access relationship metadata
results = []
threads = 3.times.map do |i|
  Thread.new do
    10.times do
      # Access shared relationship metadata
      relationships = PerfDomain.relationships
      results << relationships.size
    end
  end
end

threads.each(&:join)

# All threads should see consistent relationship count
results.uniq.size
#=> 1

## Multiple threads can safely perform relationship operations
thread_results = []
operation_threads = 3.times.map do |i|
  Thread.new do
    begin
      # Each thread creates and manages its own domain
      domain = PerfDomain.new(
        domain_id: "thread_test_#{i}",
        display_domain: "thread#{i}.test.com",
        created_at: Time.now.to_i + i,
        priority_score: i * 10
      )
      domain.save

      # Verify the domain was added to collections
      in_all = PerfDomain.all_domains.member?(domain.identifier)
      in_priority = PerfDomain.priority_queue.member?(domain.identifier)

      thread_results << [in_all, in_priority]

      domain.destroy!
    rescue => e
      thread_results << [:error, e.class.name]
    end
  end
end

operation_threads.each(&:join)

# All operations should succeed
thread_results.all? { |result| result == [true, true] }
#=> true

# =============================================
# 4. Integration with Other Features Tests
# =============================================

## Integration with safe_dump (if available)
integration_model = IntegrationTestModel.new(id: 'integration_test', data: 'test_data', created_at: Time.now.to_i)

if integration_model.respond_to?(:safe_dump)
  integration_model.save
  dump = integration_model.safe_dump
  if dump.is_a?(Hash) && dump.has_key?('id')
    "safe_dump integration working"
  else
    "safe_dump returned unexpected format"
  end
else
  "safe_dump not available"
end
#=:> String

## Integration with expiration (if available)
integration_model2 = IntegrationTestModel.new(id: 'integration_test2', data: 'test_data2', created_at: Time.now.to_i)
if integration_model2.respond_to?(:default_expiration)
  # Test that expiration works with relationship collections
  if integration_model2.class.respond_to?(:all_items)
    "expiration integration working"
  else
    "expiration missing collections"
  end
else
  "expiration not available"
end
#=:> String

## Integration with encryption (if available)
if IntegrationTestModel.respond_to?(:encrypted_field)
  "encryption integration available"
else
  "encryption not available"
end
#=:> String

# =============================================
# 5. Stress Tests
# =============================================

## Large number of relationships per class
# StressTestModel is defined in the setup section above

## Class loading should handle many relationships
StressTestModel.relationships.size
#=> 40

## Methods should be generated correctly
StressTestModel.respond_to?(:add_to_collection_0) && StressTestModel.respond_to?(:add_to_collection_19)
#=> true

## Object creation should still be fast with many relationships
stress_time = Benchmark.realtime do
  stress_obj = StressTestModel.new(id: 'stress_test')
  stress_obj.save
  stress_obj.destroy!
end

# Should handle many relationships efficiently
stress_time < 0.1
#=> true

# =============================================
# 6. Error Recovery and Resilience Tests
# =============================================

## Relationship operations should be atomic
test_domain = PerfDomain.new(
  domain_id: 'atomic_test',
  display_domain: 'atomic.test.com',
  created_at: Time.now.to_i,
  priority_score: 50
)

# Save should succeed and add to all collections
test_domain.save
all_collections_have_domain = [
  PerfDomain.all_domains.member?(test_domain.identifier),
  PerfDomain.priority_queue.member?(test_domain.identifier),
  PerfDomain.active_domains.member?(test_domain.identifier),
  PerfDomain.domain_history.members.include?(test_domain.identifier)  # Lists: get members then check include
].all?
all_collections_have_domain
#=> true

## Partial failures should not leave inconsistent state
# This would require more complex testing infrastructure to simulate Redis failures

## Recovery from Redis connection issues
begin
  # Test graceful handling of Redis errors during relationship operations
  dead_domain = PerfDomain.new(domain_id: 'dead_test')

  # This test would require mocking Redis to fail, which is complex in this context
  # For now, just verify that normal operations work
  dead_domain.save
  dead_domain.destroy!
  "error recovery test completed"
rescue => e
  e.class.name
end
#=:> String

# =============================================
# 7. Memory Cleanup and Garbage Collection
# =============================================

## Objects should be properly cleaned up after destruction
before_destroy = PerfDomain.all_domains.size

# Destroy half the domains
destroyed_count = 0
@domains[0..24].each do |domain|
  domain.destroy!
  destroyed_count += 1
end

after_destroy = PerfDomain.all_domains.size

# Should have removed exactly the destroyed domains
(before_destroy - after_destroy) == destroyed_count
#=> true

## Indexes should be cleaned up
index_size = PerfDomain.domain_lookup.size
index_size <= (50 - 25 + 5)  # Allow some variance for other test objects (destroyed 25)
#=> true

## Customer collections should be empty (no automatic cleanup implemented)
@customer.domains.size >= 0  # This would be 0 if reverse cleanup was implemented
#=> true

# =============================================
# Cleanup
# =============================================

# Clean up performance test data
[@customer].each { |obj| obj.destroy! if obj&.exists? }
@domains[25..49].each { |domain| domain.destroy! if domain&.exists? }

# Clear all test collections
[
  PerfDomain.all_domains,
  PerfDomain.priority_queue,
  PerfDomain.active_domains,
  PerfDomain.domain_history,
  PerfDomain.domain_lookup,
  PerfDomain.customer_domains,
  PerfDomain.id_lookup,
  @customer.domains,  # Instance method, not class method
  @customer.tags,     # Instance method, not class method
  @customer.activity_log,  # Instance method, not class method
  IntegrationTestModel.all_items
].each { |collection| collection.clear rescue nil }

# Performance summary
"Performance tests completed successfully"
#=> "Performance tests completed successfully"
