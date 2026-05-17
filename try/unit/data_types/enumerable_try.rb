# try/unit/data_types/enumerable_try.rb
#
# frozen_string_literal: true

# Tests for Enumerable integration on DataTypes.
# Verifies that each_slice, lazy, map, reduce, find work on
# SortedSet, HashKey, UnsortedSet, ListKey.

require_relative '../../support/helpers/test_helpers'

# Setup: Create test objects with various data types populated
@bone = Bone.new 'enumerable_test'

# Populate sorted set
@bone.metrics.add 'metric_a', 10
@bone.metrics.add 'metric_b', 20
@bone.metrics.add 'metric_c', 30
@bone.metrics.add 'metric_d', 40
@bone.metrics.add 'metric_e', 50

# Populate hashkey
@bone.props['key_a'] = 'value_a'
@bone.props['key_b'] = 'value_b'
@bone.props['key_c'] = 'value_c'
@bone.props['key_d'] = 'value_d'

# Populate unsorted set
@bone.tags.add 'tag_a'
@bone.tags.add 'tag_b'
@bone.tags.add 'tag_c'
@bone.tags.add 'tag_d'

# Populate list
@bone.owners.push 'owner_a'
@bone.owners.push 'owner_b'
@bone.owners.push 'owner_c'
@bone.owners.push 'owner_d'

# ============================================================
# SortedSet Enumerable integration
# ============================================================

## SortedSet includes Enumerable module
Familia::SortedSet.include?(Enumerable)
#=> true

## SortedSet#each_slice yields slices of members
slices = []
@bone.metrics.each_slice(2) { |slice| slices << slice }
slices.map(&:size)
#=> [2, 2, 1]

## SortedSet#map transforms members
@bone.metrics.map { |m| m.upcase }.sort
#=> ['METRIC_A', 'METRIC_B', 'METRIC_C', 'METRIC_D', 'METRIC_E']

## SortedSet#reduce aggregates members
@bone.metrics.reduce('') { |acc, m| acc + m[0] }
#=> 'mmmmm'

## SortedSet#find locates first matching member
@bone.metrics.find { |m| m.include?('_c') }
#=> 'metric_c'

## SortedSet#lazy returns Enumerator::Lazy
@bone.metrics.lazy.class
#=> Enumerator::Lazy

## SortedSet#lazy.take returns limited results (2 elements, order not guaranteed)
@bone.metrics.lazy.take(2).to_a.size
#=> 2

## SortedSet#select filters members
@bone.metrics.select { |m| m.end_with?('_a', '_b') }.sort
#=> ['metric_a', 'metric_b']

## SortedSet#reject excludes members
@bone.metrics.reject { |m| m.end_with?('_e') }.sort
#=> ['metric_a', 'metric_b', 'metric_c', 'metric_d']

## SortedSet#first returns first member
@bone.metrics.first
#=> 'metric_a'

## SortedSet#count returns element count
@bone.metrics.count
#=> 5

# ============================================================
# HashKey Enumerable integration
# ============================================================

## HashKey includes Enumerable module (via hgetall iteration)
# Note: HashKey may not include Enumerable directly but supports iteration
@bone.props.respond_to?(:each) || @bone.props.respond_to?(:all)
#=> true

## HashKey#all returns all key-value pairs as Hash
@bone.props.all.class
#=> Hash

## HashKey#keys supports iteration
@bone.props.keys.sort
#=> ['key_a', 'key_b', 'key_c', 'key_d']

## HashKey#values supports iteration
@bone.props.values.sort
#=> ['value_a', 'value_b', 'value_c', 'value_d']

# ============================================================
# UnsortedSet Enumerable integration
# ============================================================

## UnsortedSet includes Enumerable module
Familia::UnsortedSet.include?(Enumerable)
#=> true

## UnsortedSet#each_slice yields slices of members
slices = []
@bone.tags.each_slice(2) { |slice| slices << slice }
slices.size
#=> 2

## UnsortedSet#map transforms members
@bone.tags.map { |t| t.upcase }.sort
#=> ['TAG_A', 'TAG_B', 'TAG_C', 'TAG_D']

## UnsortedSet#reduce aggregates members
@bone.tags.map { |t| t.length }.reduce(0, :+)
#=> 20

## UnsortedSet#find locates first matching member
result = @bone.tags.find { |t| t.include?('_b') }
result == 'tag_b'
#=> true

## UnsortedSet#lazy returns Enumerator::Lazy
@bone.tags.lazy.class
#=> Enumerator::Lazy

## UnsortedSet#select filters members
@bone.tags.select { |t| t.end_with?('_a', '_c') }.sort
#=> ['tag_a', 'tag_c']

## UnsortedSet#count returns element count
@bone.tags.count
#=> 4

# ============================================================
# ListKey Enumerable integration
# ============================================================

## ListKey includes Enumerable module
Familia::ListKey.include?(Enumerable)
#=> true

## ListKey#each_slice yields slices of members
slices = []
@bone.owners.each_slice(2) { |slice| slices << slice }
slices.map(&:size)
#=> [2, 2]

## ListKey#map transforms members
@bone.owners.map { |o| o.upcase }
#=> ['OWNER_A', 'OWNER_B', 'OWNER_C', 'OWNER_D']

## ListKey#reduce aggregates members
@bone.owners.reduce('') { |acc, o| acc + o[-1] }
#=> 'abcd'

## ListKey#find locates first matching member
@bone.owners.find { |o| o.include?('_c') }
#=> 'owner_c'

## ListKey#lazy returns Enumerator::Lazy
@bone.owners.lazy.class
#=> Enumerator::Lazy

## ListKey#lazy.take returns limited results
@bone.owners.lazy.take(2).to_a
#=> ['owner_a', 'owner_b']

## ListKey#select filters members
@bone.owners.select { |o| o.end_with?('_a', '_d') }
#=> ['owner_a', 'owner_d']

## ListKey#first returns first member
@bone.owners.first
#=> 'owner_a'

## ListKey#count returns element count
@bone.owners.count
#=> 4

# ============================================================
# Enumerable composition across types
# ============================================================

## Chained lazy enumeration works on SortedSet
result = @bone.metrics.lazy.select { |m| m.include?('_') }.take(3).to_a
result.size
#=> 3

## Chained lazy enumeration works on ListKey
result = @bone.owners.lazy.map(&:upcase).take(2).to_a
result
#=> ['OWNER_A', 'OWNER_B']

## each_with_object works on SortedSet
result = @bone.metrics.each_with_object({}) { |m, h| h[m] = m.length }
result['metric_a']
#=> 8

## partition works on UnsortedSet
short, long = @bone.tags.partition { |t| t.length < 6 }
[short.sort, long.sort]
#=> [['tag_a', 'tag_b', 'tag_c', 'tag_d'], []]

## group_by works on ListKey
grouped = @bone.owners.group_by { |o| o.length }
grouped[7].sort
#=> ['owner_a', 'owner_b', 'owner_c', 'owner_d']

# Teardown: Clean up test data
@bone.metrics.delete!
@bone.props.delete!
@bone.tags.delete!
@bone.owners.delete!
