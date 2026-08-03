# try/unit/data_types/enumerable_consistency/large_scale_consistency_try.rb
#
# frozen_string_literal: true

# Consistency tests verifying that cursor-based `each` produces identical results
# to legacy methods at 10k, 100k, and 1M item scales.
#
# These tests catch edge cases that only manifest with large datasets:
# - Pagination boundary errors across many SCAN iterations
# - Memory-efficient iteration correctness
# - SCAN cursor handling with high cardinality
#
# Uses streaming comparison (checksums) to avoid materializing large collections.

require_relative '../../../support/helpers/test_helpers'
require 'digest'
require 'set'

# Number of commands to buffer per pipeline round-trip when bulk-loading.
#
# The setups here load 10k-1M items. Doing that as a SINGLE pipelined block
# buffers the whole command batch client-side and forces the server to ingest
# all of it before the first reply comes back. On a busy/shared CI database that
# round-trip can exceed the client read timeout -- surfacing as
# `Redis::ConnectionError: Waited 5 seconds` during setup, which then cascades
# into the dependent assertions (the collection was never fully populated). This
# is the standard Redis pipelining guidance: prefer many bounded pipelines over
# one unbounded one. 10k keeps each round-trip small and fast while still
# amortizing away per-command latency, and mirrors the `batch_size: 10000` the
# iteration assertions use.
BULK_PIPELINE_BATCH = 10_000

# Bulk-load `count` items in bounded pipeline batches. Yields the pipeline and
# the current index for each item; batches run in ascending index order and each
# pipeline completes before the next begins, so insertion order is preserved
# (matters for ListKey's ordered checks).
def bulk_pipeline(dbclient, count, batch_size: BULK_PIPELINE_BATCH)
  (0...count).each_slice(batch_size) do |batch|
    dbclient.pipelined do |pipe|
      batch.each { |i| yield pipe, i }
    end
  end
end

# Helper to bulk-insert into an UnsortedSet via pipelining
def bulk_add_to_set(set, count, prefix: 'item')
  bulk_pipeline(set.dbclient, count) do |pipe, i|
    pipe.sadd(set.dbkey, Familia::JsonSerializer.dump("#{prefix}_#{i.to_s.rjust(7, '0')}"))
  end
end

# Helper to bulk-insert into a SortedSet via pipelining
def bulk_add_to_zset(zset, count, prefix: 'metric')
  bulk_pipeline(zset.dbclient, count) do |pipe, i|
    pipe.zadd(zset.dbkey, i.to_f, Familia::JsonSerializer.dump("#{prefix}_#{i.to_s.rjust(7, '0')}"))
  end
end

# Helper to bulk-insert into a ListKey via pipelining
def bulk_push_to_list(list, count, prefix: 'owner')
  bulk_pipeline(list.dbclient, count) do |pipe, i|
    pipe.rpush(list.dbkey, Familia::JsonSerializer.dump("#{prefix}_#{i.to_s.rjust(7, '0')}"))
  end
end

# Helper to bulk-insert into a HashKey via pipelining
def bulk_set_hash(hash, count, prefix: 'field')
  bulk_pipeline(hash.dbclient, count) do |pipe, i|
    pipe.hset(hash.dbkey, "#{prefix}_#{i.to_s.rjust(7, '0')}", Familia::JsonSerializer.dump("value_#{i}"))
  end
end

# Compute order-independent checksum by XORing item hashes
def xor_checksum(enumerable)
  checksum = 0
  enumerable.each { |item| checksum ^= item.hash }
  checksum
end

# Compute order-dependent checksum for lists
def ordered_checksum(enumerable)
  digest = Digest::SHA256.new
  enumerable.each { |item| digest.update(item.to_s) }
  digest.hexdigest
end

# ============================================================
# 10,000 items - full materialization acceptable at this scale
# ============================================================

## Setup 10k UnsortedSet
@bone_10k = Bone.new 'large_scale_10k'
bulk_add_to_set(@bone_10k.tags, 10_000)
@bone_10k.tags.element_count
#=> 10000

## UnsortedSet 10k: each.to_a matches members (batch_size=100)
new_result = @bone_10k.tags.each(batch_size: 100).to_a.sort
members_result = @bone_10k.tags.members.sort
new_result == members_result
#=> true

## UnsortedSet 10k: each.to_a matches members (batch_size=1000)
new_result = @bone_10k.tags.each(batch_size: 1000).to_a.sort
members_result = @bone_10k.tags.members.sort
new_result == members_result
#=> true

## UnsortedSet 10k: no duplicates in each iteration
each_result = @bone_10k.tags.each.to_a
each_result.size == each_result.uniq.size
#=> true

## Cleanup 10k UnsortedSet
@bone_10k.tags.delete!
true
#=> true

## Setup 10k SortedSet
@bone_10k_ss = Bone.new 'large_scale_10k_sorted'
bulk_add_to_zset(@bone_10k_ss.metrics, 10_000)
@bone_10k_ss.metrics.element_count
#=> 10000

## SortedSet 10k: each.to_a matches members (batch_size=100)
new_result = @bone_10k_ss.metrics.each(batch_size: 100).to_a.sort
members_result = @bone_10k_ss.metrics.members.sort
new_result == members_result
#=> true

## SortedSet 10k: each with since/until filter
new_result = @bone_10k_ss.metrics.each(since: 5000.0, until: 7500.0).to_a.sort
expected = @bone_10k_ss.metrics.rangebyscore(5000.0, 7500.0).sort
new_result == expected
#=> true

## Cleanup 10k SortedSet
@bone_10k_ss.metrics.delete!
true
#=> true

## Setup 10k ListKey
@bone_10k_list = Bone.new 'large_scale_10k_list'
bulk_push_to_list(@bone_10k_list.owners, 10_000)
@bone_10k_list.owners.element_count
#=> 10000

## ListKey 10k: each.to_a matches members (exact order)
new_result = @bone_10k_list.owners.each(batch_size: 100).to_a
members_result = @bone_10k_list.owners.members
new_result == members_result
#=> true

## ListKey 10k: order preserved across batch boundaries
new_result = @bone_10k_list.owners.each(batch_size: 333).to_a
members_result = @bone_10k_list.owners.members
new_result == members_result
#=> true

## Cleanup 10k ListKey
@bone_10k_list.owners.delete!
true
#=> true

## Setup 10k HashKey
@bone_10k_hash = Bone.new 'large_scale_10k_hash'
bulk_set_hash(@bone_10k_hash.props, 10_000)
@bone_10k_hash.props.field_count
#=> 10000

## HashKey 10k: each.to_h matches hgetall
each_hash = @bone_10k_hash.props.each(batch_size: 100).to_h
hgetall_hash = @bone_10k_hash.props.hgetall
each_hash == hgetall_hash
#=> true

## HashKey 10k: matching filter works at scale
each_hash = @bone_10k_hash.props.each(matching: 'field_00001*', batch_size: 100).to_h
expected = @bone_10k_hash.props.hgetall.select { |k, _| k.start_with?('field_00001') }
each_hash == expected
#=> true

## Cleanup 10k HashKey
@bone_10k_hash.props.delete!
true
#=> true

# ============================================================
# 100,000 items - streaming comparison via checksums
# ============================================================

## Setup 100k UnsortedSet
@bone_100k = Bone.new 'large_scale_100k'
bulk_add_to_set(@bone_100k.tags, 100_000)
@bone_100k.tags.element_count
#=> 100000

## UnsortedSet 100k: count matches
@bone_100k.tags.each(batch_size: 10000).count == @bone_100k.tags.element_count
#=> true

## UnsortedSet 100k: streaming checksum matches members checksum
each_checksum = xor_checksum(@bone_100k.tags.each(batch_size: 10000))
members_checksum = xor_checksum(@bone_100k.tags.members)
each_checksum == members_checksum
#=> true

## UnsortedSet 100k: no duplicates (streaming count vs unique count)
seen = Set.new
@bone_100k.tags.each(batch_size: 10000) { |item| seen.add(item) }
seen.size == 100_000
#=> true

## Cleanup 100k UnsortedSet
@bone_100k.tags.delete!
true
#=> true

## Setup 100k SortedSet
@bone_100k_ss = Bone.new 'large_scale_100k_sorted'
bulk_add_to_zset(@bone_100k_ss.metrics, 100_000)
@bone_100k_ss.metrics.element_count
#=> 100000

## SortedSet 100k: count matches
@bone_100k_ss.metrics.each(batch_size: 10000).count == @bone_100k_ss.metrics.element_count
#=> true

## SortedSet 100k: streaming checksum matches members checksum
each_checksum = xor_checksum(@bone_100k_ss.metrics.each(batch_size: 10000))
members_checksum = xor_checksum(@bone_100k_ss.metrics.members)
each_checksum == members_checksum
#=> true

## SortedSet 100k: since/until filter count is correct
# Score range 25000-75000 should contain 50001 items (inclusive)
filter_count = @bone_100k_ss.metrics.each(since: 25000.0, until: 75000.0, batch_size: 10000).count
filter_count == 50001
#=> true

## Cleanup 100k SortedSet
@bone_100k_ss.metrics.delete!
true
#=> true

## Setup 100k ListKey
@bone_100k_list = Bone.new 'large_scale_100k_list'
bulk_push_to_list(@bone_100k_list.owners, 100_000)
@bone_100k_list.owners.element_count
#=> 100000

## ListKey 100k: count matches
@bone_100k_list.owners.each(batch_size: 10000).count == @bone_100k_list.owners.element_count
#=> true

## ListKey 100k: ordered checksum matches members checksum
each_checksum = ordered_checksum(@bone_100k_list.owners.each(batch_size: 10000))
members_checksum = ordered_checksum(@bone_100k_list.owners.members)
each_checksum == members_checksum
#=> true

## Cleanup 100k ListKey
@bone_100k_list.owners.delete!
true
#=> true

## Setup 100k HashKey
@bone_100k_hash = Bone.new 'large_scale_100k_hash'
bulk_set_hash(@bone_100k_hash.props, 100_000)
@bone_100k_hash.props.field_count
#=> 100000

## HashKey 100k: count matches
@bone_100k_hash.props.each(batch_size: 10000).count == @bone_100k_hash.props.field_count
#=> true

## HashKey 100k: streaming checksum matches hgetall checksum
each_checksum = xor_checksum(@bone_100k_hash.props.each(batch_size: 10000).map { |k, v| "#{k}:#{v}" })
hgetall_checksum = xor_checksum(@bone_100k_hash.props.hgetall.map { |k, v| "#{k}:#{v}" })
each_checksum == hgetall_checksum
#=> true

## Cleanup 100k HashKey
@bone_100k_hash.props.delete!
true
#=> true

# ============================================================
# 1,000,000 items - pure streaming, no materialization
# ============================================================

## Setup 1M UnsortedSet
@bone_1m = Bone.new 'large_scale_1m'
bulk_add_to_set(@bone_1m.tags, 1_000_000)
@bone_1m.tags.element_count
#=> 1000000

## UnsortedSet 1M: streaming covers every member (SSCAN is at-least-once)
# SSCAN guarantees at-least-once delivery, not exactly-once: a member can be
# yielded more than once while the hash table rehashes (likely right after a
# 1M-member bulk load), so an exact `.count == 1_000_000` is inherently racy.
# Assert the semantics SSCAN actually provides: raw yield count is at least
# the cardinality, and the deduplicated count matches element_count exactly.
raw_count = 0
unique = Set.new
@bone_1m.tags.each(batch_size: 50000) do |item|
  raw_count += 1
  unique << item
end
[raw_count >= @bone_1m.tags.element_count, unique.size]
#=> [true, 1000000]

## UnsortedSet 1M: streaming XOR checksum is non-zero (sanity check)
checksum = 0
@bone_1m.tags.each(batch_size: 50000) { |item| checksum ^= item.hash }
checksum != 0
#=> true

## UnsortedSet 1M: spot-check random members exist in iteration
samples = @bone_1m.tags.dbclient.srandmember(@bone_1m.tags.dbkey, 10).map { |v| Familia::JsonSerializer.parse(v) }
found = samples.to_set
@bone_1m.tags.each(batch_size: 50000) { |item| found.delete(item) }
found.empty?
#=> true

## Cleanup 1M UnsortedSet
@bone_1m.tags.delete!
true
#=> true
