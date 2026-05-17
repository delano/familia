# try/unit/data_types/each_record_try.rb
#
# frozen_string_literal: true

# Tests for DataType#each_record - yields loaded Horreum records.
# This method batches fetches via load_multi and handles ghost instances.

require_relative '../../support/helpers/test_helpers'

# Setup: Define test class for empty instances testing
class EachRecordEmptyTest < Familia::Horreum
  identifier_field :testid
  field :testid
end

# Setup: Create multiple Customer records in the instances timeline
# Use a unique prefix to avoid test pollution
@test_prefix = "each_record_test_#{Time.now.to_i}"

# Create and save test customers
@customers = []
5.times do |i|
  c = Customer.new(
    custid: "#{@test_prefix}_customer_#{i}",
    email: "customer#{i}@example.com",
    name: "Customer #{i}",
    role: i.even? ? 'admin' : 'user'
  )
  c.save
  @customers << c
end

# Get the score (timestamp) of a known record for filter tests
@known_score = Customer.instances.score(@customers[2].identifier)

# ============================================================
# Basic each_record iteration
# ============================================================

## each_record yields Horreum instances (not raw IDs)
records = []
Customer.instances.each_record { |r| records << r if r.custid.start_with?(@test_prefix) }
records.all? { |r| r.is_a?(Customer) }
#=> true

## each_record yields records with correct data
records = []
Customer.instances.each_record { |r| records << r if r.custid.start_with?(@test_prefix) }
records.map { |r| r.custid }.sort == @customers.map(&:custid).sort
#=> true

## each_record returns Enumerator when no block given
result = Customer.instances.each_record
result.class
#=> Enumerator

## each_record Enumerator can be chained
# Take first 3 records from our test set
records = Customer.instances.each_record.select { |r| r.custid.start_with?(@test_prefix) }.take(3)
records.size
#=> 3

# ============================================================
# batch_size parameter
# ============================================================

## each_record with batch_size smaller than total records
records = []
Customer.instances.each_record(batch_size: 2) { |r| records << r if r.custid.start_with?(@test_prefix) }
records.size
#=> 5

## each_record with batch_size larger than total records
records = []
Customer.instances.each_record(batch_size: 100) { |r| records << r if r.custid.start_with?(@test_prefix) }
records.size
#=> 5

## each_record with batch_size of 1
records = []
Customer.instances.each_record(batch_size: 1) { |r| records << r if r.custid.start_with?(@test_prefix) }
records.size
#=> 5

## each_record with default batch_size
records = []
Customer.instances.each_record { |r| records << r if r.custid.start_with?(@test_prefix) }
records.size
#=> 5

# ============================================================
# write_size parameter for pipelining
# ============================================================

## each_record with write_size for batched writes
# write_size controls how many records are processed before flushing writes
records = []
Customer.instances.each_record(write_size: 2) { |r| records << r if r.custid.start_with?(@test_prefix) }
records.size
#=> 5

## each_record with write_size: nil for serial execution
# Serial execution processes one at a time without batching
records = []
Customer.instances.each_record(write_size: nil) { |r| records << r if r.custid.start_with?(@test_prefix) }
records.size
#=> 5

## each_record with both batch_size and write_size
records = []
Customer.instances.each_record(batch_size: 3, write_size: 2) { |r| records << r if r.custid.start_with?(@test_prefix) }
records.size
#=> 5

# ============================================================
# Combined with filters (on SortedSet)
# ============================================================

## each_record with since: filter includes boundary record
# Only records with score >= since should be yielded
records = []
Customer.instances.each_record(since: @known_score) { |r| records << r if r.custid.start_with?(@test_prefix) }
# Customer 2 (whose score defines the boundary) must be included
records.map(&:custid).include?(@customers[2].custid)
#=> true

## each_record with until: filter includes boundary record
# Only records with score <= until should be yielded
records = []
Customer.instances.each_record(until: @known_score) { |r| records << r if r.custid.start_with?(@test_prefix) }
# Customer 2 (whose score defines the boundary) must be included
records.map(&:custid).include?(@customers[2].custid)
#=> true

## each_record with since: and until: exact match returns only matching scores
# Exact score match - only records at exactly @known_score
records = []
Customer.instances.each_record(since: @known_score, until: @known_score) { |r| records << r if r.custid.start_with?(@test_prefix) }
# Customer 2 must be included, and all records must have exactly @known_score
records.map(&:custid).include?(@customers[2].custid) &&
  records.all? { |r| Customer.instances.score(r.identifier) == @known_score }
#=> true

# ============================================================
# Empty set handling
# ============================================================

## each_record on empty instances set returns empty
records = []
EachRecordEmptyTest.instances.each_record { |r| records << r }
records
#=> []

## each_record Enumerator on empty set is empty
EachRecordEmptyTest.instances.each_record.to_a
#=> []

# ============================================================
# Record data integrity
# ============================================================

## each_record yields records with all fields populated
records = []
Customer.instances.each_record { |r| records << r if r.custid == @customers[0].custid }
record = records.first
[record.email, record.name, record.role] == [@customers[0].email, @customers[0].name, @customers[0].role]
#=> true

## each_record yields records that can be modified and saved
records = []
Customer.instances.each_record { |r| records << r if r.custid == @customers[1].custid }
record = records.first
original_name = record.name
record.name = "Modified #{original_name}"
record.save
# Verify the change persisted
reloaded = Customer.find_by_id(@customers[1].custid)
result = reloaded.name == "Modified #{original_name}"
# Restore original name for subsequent tests
reloaded.name = original_name
reloaded.save
result
#=> true

## each_record records respond to instance methods
records = []
Customer.instances.each_record { |r| records << r if r.custid == @customers[0].custid }
record = records.first
record.respond_to?(:active?)
#=> true

# ============================================================
# Enumerable composition
# ============================================================

## each_record can be lazy enumerated
result = Customer.instances.each_record.lazy.select { |r| r.custid.start_with?(@test_prefix) }.take(2).to_a
result.size
#=> 2

## each_record can be chained with map and sorted
# Note: Order from Redis may vary, so we sort after selecting
result = Customer.instances.each_record.select { |r| r.custid.start_with?(@test_prefix) }.map(&:name).sort.take(3)
result
#=> ['Customer 0', 'Customer 1', 'Customer 2']

## each_record works with each_slice
batches = []
Customer.instances.each_record.select { |r| r.custid.start_with?(@test_prefix) }.each_slice(2) { |b| batches << b.size }
batches
#=> [2, 2, 1]

# ============================================================
# Ghost instance filtering
# NOTE: These tests verify behavior when hash keys are missing
# but identifiers remain in the instances timeline (ghost entries)
# ============================================================

## Ghost instances are filtered (hash key deleted, instances entry remains)
# Create a ghost by saving then deleting the hash key
@ghost_prefix = "ghost_test_#{Time.now.to_i}"
ghost_customer = Customer.new(
  custid: "#{@ghost_prefix}_ghost",
  email: 'ghost@example.com',
  name: 'Ghost Customer'
)
ghost_customer.save
# Delete the hash key to create a ghost entry
Familia.dbclient(Customer.logical_database).del(ghost_customer.dbkey)
# The ghost should not be yielded because its hash key is gone
records = []
Customer.instances.each_record { |r| records << r if r&.custid&.start_with?(@ghost_prefix) }
records.size
#=> 0

## each_record continues iteration despite ghost entries
# All 5 test customers should still be yielded even if ghosts exist
records = []
Customer.instances.each_record { |r| records << r if r&.custid&.start_with?(@test_prefix) }
records.size
#=> 5

# Teardown: Clean up test data
@customers.each { |c| c.destroy! rescue nil }
Customer.instances.remove("#{@ghost_prefix}_ghost") rescue nil
