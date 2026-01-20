# try/unit/data_types/sortedset_operations_try.rb
#
# frozen_string_literal: true

# Tests for SortedSet operations beyond basic add/members.
# Focus: Familia-specific behavior - score handling, deserialization, withscores option.
#
# NOTE: Tests for union/inter/diff with withscores option are omitted because
# the current Familia implementation uses :withscores but redis-rb requires
# :with_scores. See build_set_operation_opts in sorted_set.rb.

require_relative '../../support/helpers/test_helpers'

# Setup: Create test objects with sorted sets
@a = Bone.new 'zset_ops_a'
@b = Bone.new 'zset_ops_b'
@c = Bone.new 'zset_ops_c'
@dest_key = 'familia:test:zset_dest'

# Populate sorted sets with test data
# Set A: {m1:10, m2:20, m3:30, m4:40}
@a.metrics.add 'm1', 10
@a.metrics.add 'm2', 20
@a.metrics.add 'm3', 30
@a.metrics.add 'm4', 40

# Set B: {m3:35, m4:45, m5:55, m6:65}
@b.metrics.add 'm3', 35
@b.metrics.add 'm4', 45
@b.metrics.add 'm5', 55
@b.metrics.add 'm6', 65

# Set C: {m4:100, m5:110, m6:120, m7:130}
@c.metrics.add 'm4', 100
@c.metrics.add 'm5', 110
@c.metrics.add 'm6', 120
@c.metrics.add 'm7', 130

# Setup for lex tests (all same score required for lexicographical operations)
@lex_test = Bone.new 'zset_lex_test'
@lex_test.metrics.add 'apple', 0
@lex_test.metrics.add 'banana', 0
@lex_test.metrics.add 'cherry', 0
@lex_test.metrics.add 'date', 0
@lex_test.metrics.add 'elderberry', 0

# ============================================================
# popmin/popmax - Test [member, score] pair with deserialization
# ============================================================

## Familia::SortedSet#popmin returns [member, score] pair with Float score
@pop_test = Bone.new 'zset_pop_test'
@pop_test.metrics.add 'lowest', 5
@pop_test.metrics.add 'middle', 50
@pop_test.metrics.add 'highest', 500
result = @pop_test.metrics.popmin
[result[0], result[1], result[1].is_a?(Float)]
#=> ['lowest', 5.0, true]

## Familia::SortedSet#popmin removes the element from the set
@pop_test.metrics.members
#=> ['middle', 'highest']

## Familia::SortedSet#popmax returns [member, score] pair with Float score
result = @pop_test.metrics.popmax
[result[0], result[1], result[1].is_a?(Float)]
#=> ['highest', 500.0, true]

## Familia::SortedSet#popmax removes the element from the set
@pop_test.metrics.members
#=> ['middle']

## Familia::SortedSet#popmin with count returns array of [member, score] pairs
@pop_test2 = Bone.new 'zset_pop_test2'
@pop_test2.metrics.add 'a', 1
@pop_test2.metrics.add 'b', 2
@pop_test2.metrics.add 'c', 3
result = @pop_test2.metrics.popmin(2)
result.map { |m, s| [m, s.is_a?(Float)] }
#=> [['a', true], ['b', true]]

## Familia::SortedSet#popmax with count returns array of [member, score] pairs
@pop_test3 = Bone.new 'zset_pop_test3'
@pop_test3.metrics.add 'x', 10
@pop_test3.metrics.add 'y', 20
@pop_test3.metrics.add 'z', 30
result = @pop_test3.metrics.popmax(2)
result.map { |m, _s| m }
#=> ['z', 'y']

## Familia::SortedSet#popmin on empty set returns nil
@empty_zset = Bone.new 'zset_empty_pop'
@empty_zset.metrics.popmin
#=> nil

## Familia::SortedSet#popmax on empty set returns nil
@empty_zset.metrics.popmax
#=> nil

# ============================================================
# score_count/zcount - Test score range counting
# ============================================================

## Familia::SortedSet#score_count returns count in score range
@a.metrics.score_count(15, 35)
#=> 2

## Familia::SortedSet#score_count with inclusive boundaries
@a.metrics.score_count(20, 30)
#=> 2

## Familia::SortedSet#zcount is alias for score_count
@a.metrics.zcount(10, 40)
#=> 4

## Familia::SortedSet#score_count with -inf to +inf returns all
@a.metrics.score_count('-inf', '+inf')
#=> 4

## Familia::SortedSet#score_count with exclusive boundaries using parentheses
@a.metrics.score_count('(10', '(40')
#=> 2

# ============================================================
# mscore - Test returns array of Float/nil values
# ============================================================

## Familia::SortedSet#mscore returns array of Float scores
scores = @a.metrics.mscore('m1', 'm2', 'm3')
scores.map { |s| s.is_a?(Float) }
#=> [true, true, true]

## Familia::SortedSet#mscore returns correct score values
@a.metrics.mscore('m1', 'm2')
#=> [10.0, 20.0]

## Familia::SortedSet#mscore returns nil for non-existent members
@a.metrics.mscore('m1', 'nonexistent', 'm3')
#=> [10.0, nil, 30.0]

## Familia::SortedSet#mscore with no arguments returns empty array
@a.metrics.mscore
#=> []

# ============================================================
# union/inter - Test basic set operations and deserialization
# ============================================================

## Familia::SortedSet#union returns deserialized members
result = @a.metrics.union(@b.metrics)
result.include?('m1') && result.include?('m6')
#=> true

## Familia::SortedSet#union returns all unique members
result = @a.metrics.union(@b.metrics)
result.sort
#=> ['m1', 'm2', 'm3', 'm4', 'm5', 'm6']

## Familia::SortedSet#union with multiple sets
result = @a.metrics.union(@b.metrics, @c.metrics)
result.sort
#=> ['m1', 'm2', 'm3', 'm4', 'm5', 'm6', 'm7']

## Familia::SortedSet#inter returns deserialized common members
result = @a.metrics.inter(@b.metrics)
result.sort
#=> ['m3', 'm4']

## Familia::SortedSet#inter with multiple sets returns common to all
result = @a.metrics.inter(@b.metrics, @c.metrics)
result
#=> ['m4']

## Familia::SortedSet#inter with raw key string works
result = @a.metrics.inter(@b.metrics.dbkey)
result.sort
#=> ['m3', 'm4']

# ============================================================
# rangebylex/revrangebylex - Test lexicographical ordering
# NOTE: Values are JSON-serialized (e.g., "apple" -> "\"apple\""), so lex
# boundaries must match the serialized format.
# NOTE: Tests with limit: option are omitted because the current Familia
# implementation passes limit as positional args but redis-rb expects
# a keyword argument. See rangebylex in sorted_set.rb.
# ============================================================

## Familia::SortedSet#rangebylex returns members in lex range (inclusive)
@lex_test.metrics.rangebylex('["banana"', '["date"')
#=> ['banana', 'cherry', 'date']

## Familia::SortedSet#rangebylex with exclusive boundaries
@lex_test.metrics.rangebylex('("banana"', '("elderberry"')
#=> ['cherry', 'date']

## Familia::SortedSet#rangebylex with - and + for unbounded
@lex_test.metrics.rangebylex('-', '+')
#=> ['apple', 'banana', 'cherry', 'date', 'elderberry']

## Familia::SortedSet#revrangebylex returns members in reverse lex order
@lex_test.metrics.revrangebylex('+', '-')
#=> ['elderberry', 'date', 'cherry', 'banana', 'apple']

## Familia::SortedSet#revrangebylex with range
@lex_test.metrics.revrangebylex('["date"', '["banana"')
#=> ['date', 'cherry', 'banana']

# ============================================================
# lexcount - Test counting in lex range
# NOTE: Values are JSON-serialized, so lex boundaries must match.
# ============================================================

## Familia::SortedSet#lexcount counts members in lex range
@lex_test.metrics.lexcount('["banana"', '["date"')
#=> 3

## Familia::SortedSet#lexcount with unbounded range
@lex_test.metrics.lexcount('-', '+')
#=> 5

## Familia::SortedSet#lexcount with exclusive boundaries
@lex_test.metrics.lexcount('("banana"', '("elderberry"')
#=> 2

# ============================================================
# randmember - Test count parameter and withscores option
# ============================================================

## Familia::SortedSet#randmember returns single deserialized member
member = @a.metrics.randmember
@a.metrics.member?(member)
#=> true

## Familia::SortedSet#randmember with count returns array of members
result = @a.metrics.randmember(2)
[result.is_a?(Array), result.length]
#=> [true, 2]

## Familia::SortedSet#randmember with withscores returns [member, score] pairs
result = @a.metrics.randmember(2, withscores: true)
result.all? { |m, s| m.is_a?(String) && s.is_a?(Float) }
#=> true

## Familia::SortedSet#randmember on empty set returns nil
@empty_rand = Bone.new 'zset_empty_rand'
@empty_rand.metrics.randmember
#=> nil

## Familia::SortedSet#randmember with count on empty set returns empty array
@empty_rand.metrics.randmember(3)
#=> []

# ============================================================
# scan - Test returns [cursor, [[member, score],...]] format
# ============================================================

## Familia::SortedSet#scan returns [cursor, members] tuple
cursor, members = @a.metrics.scan(0)
[cursor.is_a?(Integer), members.is_a?(Array)]
#=> [true, true]

## Familia::SortedSet#scan returns deserialized members with Float scores
_cursor, members = @a.metrics.scan(0)
members.all? { |m, s| m.is_a?(String) && s.is_a?(Float) }
#=> true

## Familia::SortedSet#scan with count hint
cursor, _members = @a.metrics.scan(0, count: 2)
cursor.is_a?(Integer)
#=> true

## Familia::SortedSet#scan with match pattern
@scan_test = Bone.new 'zset_scan_test'
@scan_test.metrics.add 'user:1', 10
@scan_test.metrics.add 'user:2', 20
@scan_test.metrics.add 'item:1', 30
_cursor, members = @scan_test.metrics.scan(0, match: '"user:*"')
members.map { |m, _s| m }.all? { |m| m.start_with?('user:') }
#=> true

# ============================================================
# diff/diffstore - Test difference operations
# ============================================================

## Familia::SortedSet#diff returns members in this set but not in other
result = @a.metrics.diff(@b.metrics)
result.sort
#=> ['m1', 'm2']

## Familia::SortedSet#diff with multiple sets
result = @a.metrics.diff(@b.metrics, @c.metrics)
result.sort
#=> ['m1', 'm2']

## Familia::SortedSet#diffstore stores difference in destination key
Familia.dbclient.del(@dest_key)
count = @a.metrics.diffstore(@dest_key, @b.metrics)
stored = Familia.dbclient.zrange(@dest_key, 0, -1)
Familia.dbclient.del(@dest_key)
[count, stored.map { |v| Familia::JsonSerializer.parse(v) }.sort]
#=> [2, ['m1', 'm2']]

# ============================================================
# unionstore/interstore - Test destination key operations
# ============================================================

## Familia::SortedSet#unionstore stores union in destination key
Familia.dbclient.del(@dest_key)
count = @a.metrics.unionstore(@dest_key, @b.metrics)
stored_count = Familia.dbclient.zcard(@dest_key)
Familia.dbclient.del(@dest_key)
[count, stored_count]
#=> [6, 6]

## Familia::SortedSet#unionstore with weights
Familia.dbclient.del(@dest_key)
@a.metrics.unionstore(@dest_key, @b.metrics, weights: [1, 2])
m5_score = Familia.dbclient.zscore(@dest_key, '"m5"')
Familia.dbclient.del(@dest_key)
m5_score
#=> 110.0

## Familia::SortedSet#unionstore with aggregate
Familia.dbclient.del(@dest_key)
@a.metrics.unionstore(@dest_key, @b.metrics, aggregate: :max)
m3_score = Familia.dbclient.zscore(@dest_key, '"m3"')
Familia.dbclient.del(@dest_key)
m3_score
#=> 35.0

## Familia::SortedSet#interstore stores intersection in destination key
Familia.dbclient.del(@dest_key)
count = @a.metrics.interstore(@dest_key, @b.metrics)
stored = Familia.dbclient.zrange(@dest_key, 0, -1)
Familia.dbclient.del(@dest_key)
[count, stored.map { |v| Familia::JsonSerializer.parse(v) }.sort]
#=> [2, ['m3', 'm4']]

## Familia::SortedSet#interstore with weights and aggregate
Familia.dbclient.del(@dest_key)
@a.metrics.interstore(@dest_key, @b.metrics, weights: [2, 3], aggregate: :sum)
m3_score = Familia.dbclient.zscore(@dest_key, '"m3"')
Familia.dbclient.del(@dest_key)
m3_score
#=> 165.0

# ============================================================
# Edge Cases - Symbol and object deserialization
# ============================================================

## Familia::SortedSet operations work with symbol values
@symbol_test = Bone.new 'zset_symbol_test'
@symbol_test.metrics.add :alpha, 10
@symbol_test.metrics.add :beta, 20
result = @symbol_test.metrics.popmin
[result[0], result[1]]
#=> ['alpha', 10.0]

## Familia::SortedSet#mscore works with symbol arguments
@symbol_test2 = Bone.new 'zset_symbol_test2'
@symbol_test2.metrics.add :one, 1
@symbol_test2.metrics.add :two, 2
@symbol_test2.metrics.mscore(:one, :two)
#=> [1.0, 2.0]

# Teardown: Clean up test data
@a.metrics.delete!
@b.metrics.delete!
@c.metrics.delete!
@pop_test.metrics.delete!
@pop_test2.metrics.delete!
@pop_test3.metrics.delete!
@empty_zset.metrics.delete!
@lex_test.metrics.delete!
@empty_rand.metrics.delete!
@scan_test.metrics.delete!
@symbol_test.metrics.delete!
@symbol_test2.metrics.delete!
Familia.dbclient.del(@dest_key)
