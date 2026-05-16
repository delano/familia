# try/unit/data_types/listkey_each_try.rb
#
# frozen_string_literal: true

# Tests for ListKey#each pagination.
# ListKey iterates via LRANGE pagination since Redis doesn't support list scanning.

require_relative '../../support/helpers/test_helpers'

# Setup: Create test list with multiple elements
@bone = Bone.new 'listkey_each_test'

# Populate list with ordered elements
@bone.owners.push 'owner_01'
@bone.owners.push 'owner_02'
@bone.owners.push 'owner_03'
@bone.owners.push 'owner_04'
@bone.owners.push 'owner_05'
@bone.owners.push 'owner_06'
@bone.owners.push 'owner_07'
@bone.owners.push 'owner_08'
@bone.owners.push 'owner_09'
@bone.owners.push 'owner_10'

# Setup large list for pagination tests
@large_bone = Bone.new 'listkey_each_large_test'
100.times { |i| @large_bone.owners.push "item_#{i.to_s.rjust(3, '0')}" }

# Setup empty list for edge case tests
@empty_bone = Bone.new 'listkey_each_empty_test'

# Setup single element list
@single_bone = Bone.new 'listkey_each_single_test'
@single_bone.owners.push 'only_one'

# Setup special values list
@special_bone = Bone.new 'listkey_each_special_test'
@special_bone.owners.push ''
@special_bone.owners.push 'normal'
@special_bone.owners.push ''

# ============================================================
# Basic iteration
# ============================================================

## ListKey#each yields all elements in order
collected = []
@bone.owners.each { |o| collected << o }
collected
#=> ['owner_01', 'owner_02', 'owner_03', 'owner_04', 'owner_05', 'owner_06', 'owner_07', 'owner_08', 'owner_09', 'owner_10']

## ListKey#each returns Enumerator when no block given
result = @bone.owners.each
result.class
#=> Enumerator

## ListKey#each Enumerator yields strings
first = @bone.owners.each.first
first.is_a?(String)
#=> true

## ListKey#each preserves insertion order
collected = []
@bone.owners.each { |o| collected << o }
collected == @bone.owners.to_a
#=> true

## ListKey#each counts all elements
count = 0
@bone.owners.each { |_| count += 1 }
count
#=> 10

# ============================================================
# Large list pagination
# ============================================================

## ListKey#each handles large lists
collected = []
@large_bone.owners.each { |o| collected << o }
collected.size
#=> 100

## ListKey#each maintains order on large lists
collected = []
@large_bone.owners.each { |o| collected << o }
[collected.first, collected.last]
#=> ['item_000', 'item_099']

## ListKey#each on large list can be stopped early
collected = []
@large_bone.owners.each.take(5).each { |o| collected << o }
collected
#=> ['item_000', 'item_001', 'item_002', 'item_003', 'item_004']

# ============================================================
# Batch size variations
# ============================================================

## ListKey#each with batch_size smaller than list size
collected = []
@bone.owners.each(batch_size: 3) { |o| collected << o }
collected.size
#=> 10

## ListKey#each with batch_size larger than list size
collected = []
@bone.owners.each(batch_size: 100) { |o| collected << o }
collected.size
#=> 10

## ListKey#each with batch_size equal to list size
collected = []
@bone.owners.each(batch_size: 10) { |o| collected << o }
collected.size
#=> 10

## ListKey#each with batch_size of 1 (extreme case)
collected = []
@bone.owners.each(batch_size: 1) { |o| collected << o }
collected.size
#=> 10

## ListKey#each with batch_size preserves order
collected = []
@bone.owners.each(batch_size: 3) { |o| collected << o }
collected
#=> ['owner_01', 'owner_02', 'owner_03', 'owner_04', 'owner_05', 'owner_06', 'owner_07', 'owner_08', 'owner_09', 'owner_10']

## ListKey#each large list with small batch_size
collected = []
@large_bone.owners.each(batch_size: 7) { |o| collected << o }
collected.size
#=> 100

## ListKey#each large list maintains order with pagination
collected = []
@large_bone.owners.each(batch_size: 23) { |o| collected << o }
[collected[0], collected[22], collected[23], collected[99]]
#=> ['item_000', 'item_022', 'item_023', 'item_099']

# ============================================================
# Empty list
# ============================================================

## ListKey#each on empty list returns empty
collected = []
@empty_bone.owners.each { |o| collected << o }
collected
#=> []

## ListKey#each with batch_size on empty list returns empty
collected = []
@empty_bone.owners.each(batch_size: 10) { |o| collected << o }
collected
#=> []

# ============================================================
# Enumerable integration
# ============================================================

## ListKey#each can be chained with map
result = @bone.owners.each.map(&:upcase).take(3)
result
#=> ['OWNER_01', 'OWNER_02', 'OWNER_03']

## ListKey#each can be chained with select
result = @bone.owners.each.select { |o| o.end_with?('5', '0') }
result
#=> ['owner_05', 'owner_10']

## ListKey#each can be chained with reduce
result = @bone.owners.each.reduce('') { |acc, o| acc + o[-2..-1] }
result
#=> '01020304050607080910'

## ListKey#each supports lazy enumeration
# '_09' matches item_090 through item_099 (not item_009, which has '_00')
result = @large_bone.owners.each.lazy.select { |o| o.include?('_09') }.take(5).to_a
result
#=> ['item_090', 'item_091', 'item_092', 'item_093', 'item_094']

## ListKey#each_with_index works correctly
pairs = []
@bone.owners.each_with_index { |o, i| pairs << [i, o] }
pairs.first
#=> [0, 'owner_01']

## ListKey#each_with_index last element has correct index
pairs = []
@bone.owners.each_with_index { |o, i| pairs << [i, o] }
pairs.last
#=> [9, 'owner_10']

# ============================================================
# Edge cases
# ============================================================

## ListKey#each with single element
collected = []
@single_bone.owners.each { |o| collected << o }
collected
#=> ['only_one']

## ListKey#each with batch_size larger than single element
collected = []
@single_bone.owners.each(batch_size: 100) { |o| collected << o }
collected
#=> ['only_one']

## ListKey#each handles empty string values
collected = []
@special_bone.owners.each { |o| collected << o }
collected
#=> ['', 'normal', '']

# Teardown: Clean up test data
@bone.owners.delete!
@large_bone.owners.delete!
@empty_bone.owners.delete!
@single_bone.owners.delete!
@special_bone.owners.delete!
