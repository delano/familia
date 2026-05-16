# try/unit/data_types/sorted_set_each_try.rb
#
# frozen_string_literal: true

# Tests for SortedSet#each with since:/until: filters.
# These filters enable score-bounded iteration via ZRANGEBYSCORE.

require_relative '../../support/helpers/test_helpers'

# Setup: Create test sorted set with timestamp-like scores
@bone = Bone.new 'sorted_set_each_test'

# Use epoch timestamps as scores (simulating a timeline)
# Base time: 1704067200 = 2024-01-01 00:00:00 UTC
@base_time = 1704067200.0
@bone.metrics.add 'event_1', @base_time + 100    # 1704067300
@bone.metrics.add 'event_2', @base_time + 200    # 1704067400
@bone.metrics.add 'event_3', @base_time + 300    # 1704067500
@bone.metrics.add 'event_4', @base_time + 400    # 1704067600
@bone.metrics.add 'event_5', @base_time + 500    # 1704067700

# ============================================================
# Basic iteration without filters
# ============================================================

## SortedSet#each without filters yields all members in score order
collected = []
@bone.metrics.each { |m| collected << m }
collected
#=> ['event_1', 'event_2', 'event_3', 'event_4', 'event_5']

## SortedSet#each returns self when block given
result = @bone.metrics.each { |_| }
result.class
#=> Familia::SortedSet

## SortedSet#each returns Enumerator when no block given
result = @bone.metrics.each
result.class
#=> Enumerator

## SortedSet#each Enumerator can be chained
@bone.metrics.each.map(&:upcase).first
#=> 'EVENT_1'

# ============================================================
# since: filter (inclusive lower bound)
# ============================================================

## SortedSet#each(since:) filters by minimum score (inclusive)
collected = []
@bone.metrics.each(since: @base_time + 300) { |m| collected << m }
collected
#=> ['event_3', 'event_4', 'event_5']

## SortedSet#each(since:) with exact score includes that element
collected = []
@bone.metrics.each(since: @base_time + 200) { |m| collected << m }
collected.first
#=> 'event_2'

## SortedSet#each(since:) with score beyond max returns empty
collected = []
@bone.metrics.each(since: @base_time + 1000) { |m| collected << m }
collected
#=> []

## SortedSet#each(since:) with Time object converts to epoch
# Using a Time object that corresponds to our test timestamp
since_time = Time.at(@base_time + 400)
collected = []
@bone.metrics.each(since: since_time) { |m| collected << m }
collected
#=> ['event_4', 'event_5']

# ============================================================
# until: filter (inclusive upper bound)
# ============================================================

## SortedSet#each(until:) filters by maximum score (inclusive)
collected = []
@bone.metrics.each(until: @base_time + 300) { |m| collected << m }
collected
#=> ['event_1', 'event_2', 'event_3']

## SortedSet#each(until:) with exact score includes that element
collected = []
@bone.metrics.each(until: @base_time + 200) { |m| collected << m }
collected.last
#=> 'event_2'

## SortedSet#each(until:) with score below min returns empty
collected = []
@bone.metrics.each(until: @base_time) { |m| collected << m }
collected
#=> []

## SortedSet#each(until:) with Time object converts to epoch
until_time = Time.at(@base_time + 200)
collected = []
@bone.metrics.each(until: until_time) { |m| collected << m }
collected
#=> ['event_1', 'event_2']

# ============================================================
# Combined since: and until: filters
# ============================================================

## SortedSet#each(since:, until:) filters by score range
collected = []
@bone.metrics.each(since: @base_time + 200, until: @base_time + 400) { |m| collected << m }
collected
#=> ['event_2', 'event_3', 'event_4']

## SortedSet#each with narrow range returns single element
collected = []
@bone.metrics.each(since: @base_time + 300, until: @base_time + 300) { |m| collected << m }
collected
#=> ['event_3']

## SortedSet#each with inverted range returns empty (since > until)
collected = []
@bone.metrics.each(since: @base_time + 400, until: @base_time + 200) { |m| collected << m }
collected
#=> []

## SortedSet#each with Time objects for both bounds
since_time = Time.at(@base_time + 150)
until_time = Time.at(@base_time + 350)
collected = []
@bone.metrics.each(since: since_time, until: until_time) { |m| collected << m }
collected
#=> ['event_2', 'event_3']

# ============================================================
# Empty result scenarios
# ============================================================

## SortedSet#each on empty set returns empty array
@empty_bone = Bone.new 'sorted_set_each_empty_test'
collected = []
@empty_bone.metrics.each { |m| collected << m }
collected
#=> []

## SortedSet#each with filters on empty set returns empty array
collected = []
@empty_bone.metrics.each(since: 0, until: 1000) { |m| collected << m }
collected
#=> []

## SortedSet#each with non-overlapping filter range
collected = []
@bone.metrics.each(since: @base_time + 1000, until: @base_time + 2000) { |m| collected << m }
collected
#=> []

# ============================================================
# Batch size variations (if supported)
# ============================================================

## SortedSet#each with batch_size smaller than set
# The batch_size parameter controls cursor-based iteration internally
collected = []
@bone.metrics.each(batch_size: 2) { |m| collected << m }
collected.size
#=> 5

## SortedSet#each with batch_size larger than set
collected = []
@bone.metrics.each(batch_size: 100) { |m| collected << m }
collected.size
#=> 5

## SortedSet#each with batch_size equal to set size
collected = []
@bone.metrics.each(batch_size: 5) { |m| collected << m }
collected.size
#=> 5

## SortedSet#each with batch_size of 1 (extreme case)
collected = []
@bone.metrics.each(batch_size: 1) { |m| collected << m }
collected.size
#=> 5

# ============================================================
# Edge cases
# ============================================================

## SortedSet#each with negative scores
@neg_bone = Bone.new 'sorted_set_each_neg_test'
@neg_bone.metrics.add 'neg_1', -100
@neg_bone.metrics.add 'neg_2', -50
@neg_bone.metrics.add 'zero', 0
@neg_bone.metrics.add 'pos_1', 50
collected = []
@neg_bone.metrics.each(since: -75) { |m| collected << m }
collected
#=> ['neg_2', 'zero', 'pos_1']

## SortedSet#each with float scores
@float_bone = Bone.new 'sorted_set_each_float_test'
@float_bone.metrics.add 'f_1', 1.1
@float_bone.metrics.add 'f_2', 1.5
@float_bone.metrics.add 'f_3', 1.9
collected = []
@float_bone.metrics.each(since: 1.2, until: 1.8) { |m| collected << m }
collected
#=> ['f_2']

## SortedSet#each combined with Enumerable methods
result = @bone.metrics.each(since: @base_time + 200).map(&:upcase).take(2)
result
#=> ['EVENT_2', 'EVENT_3']

## SortedSet#each yields elements in ascending score order
collected = []
@bone.metrics.each { |m| collected << m }
collected == collected.sort_by { |m| @bone.metrics.score(m) }
#=> true

# Teardown: Clean up test data
@bone.metrics.delete!
@empty_bone.metrics.delete! if defined?(@empty_bone)
@neg_bone.metrics.delete! if defined?(@neg_bone)
@float_bone.metrics.delete! if defined?(@float_bone)
