# try/unit/data_types/unsortedset_operations_try.rb
#
# frozen_string_literal: true

# Tests for UnsortedSet set operations: intersection, union, difference,
# member_any?, scan, intercard, and store operations.

require_relative '../../support/helpers/test_helpers'

# Setup: Create test objects with sets
@a = Bone.new 'set_ops_a'
@b = Bone.new 'set_ops_b'
@c = Bone.new 'set_ops_c'
@dest = Bone.new 'set_ops_dest'

# Populate sets with test data
# Set A: {1, 2, 3, 4}
@a.tags.add 1, 2, 3, 4

# Set B: {3, 4, 5, 6}
@b.tags.add 3, 4, 5, 6

# Set C: {4, 5, 6, 7}
@c.tags.add 4, 5, 6, 7

## Familia::UnsortedSet#intersection returns common members between two sets
@a.tags.intersection(@b.tags).sort
#=> [3, 4]

## Familia::UnsortedSet#inter is an alias for intersection
@a.tags.inter(@b.tags).sort
#=> [3, 4]

## Familia::UnsortedSet#intersection with multiple sets
@a.tags.intersection(@b.tags, @c.tags).sort
#=> [4]

## Familia::UnsortedSet#intersection with raw key string
@a.tags.intersection(@b.tags.dbkey).sort
#=> [3, 4]

## Familia::UnsortedSet#union returns all unique members from both sets
@a.tags.union(@b.tags).sort
#=> [1, 2, 3, 4, 5, 6]

## Familia::UnsortedSet#union with multiple sets
@a.tags.union(@b.tags, @c.tags).sort
#=> [1, 2, 3, 4, 5, 6, 7]

## Familia::UnsortedSet#union with raw key string
@a.tags.union(@b.tags.dbkey).sort
#=> [1, 2, 3, 4, 5, 6]

## Familia::UnsortedSet#difference returns members in A but not in B
@a.tags.difference(@b.tags).sort
#=> [1, 2]

## Familia::UnsortedSet#diff is an alias for difference
@a.tags.diff(@b.tags).sort
#=> [1, 2]

## Familia::UnsortedSet#difference with multiple sets
# Returns members in A but not in B or C
@a.tags.difference(@b.tags, @c.tags).sort
#=> [1, 2]

## Familia::UnsortedSet#difference with raw key string
@a.tags.difference(@b.tags.dbkey).sort
#=> [1, 2]

## Familia::UnsortedSet#member_any? checks multiple members at once
result = @a.tags.member_any?(1, 2, 99)
[result[0], result[1], result[2]]
#=> [true, true, false]

## Familia::UnsortedSet#members? is an alias for member_any?
result = @a.tags.members?(3, 4)
result.all?
#=> true

## Familia::UnsortedSet#scan returns cursor and members
cursor, members = @a.tags.scan(0)
[cursor.is_a?(Integer), members.sort]
#=> [true, [1, 2, 3, 4]]

## Familia::UnsortedSet#scan with count hint
cursor, members = @a.tags.scan(0, count: 2)
cursor.is_a?(Integer)
#=> true

## Familia::UnsortedSet#intercard returns intersection count without retrieving members
@a.tags.intercard(@b.tags)
#=> 2

## Familia::UnsortedSet#intersection_cardinality is an alias for intercard
@a.tags.intersection_cardinality(@b.tags, @c.tags)
#=> 1

## Familia::UnsortedSet#intercard with limit stops early
# With limit 1, counting stops after finding 1 common element
@a.tags.intercard(@b.tags, limit: 1)
#=> 1

## Familia::UnsortedSet#interstore stores intersection in destination
@dest.tags.delete!
result = @a.tags.interstore(@dest.tags, @b.tags)
[result, @dest.tags.members.sort]
#=> [2, [3, 4]]

## Familia::UnsortedSet#intersection_store is an alias for interstore
@dest.tags.delete!
@a.tags.intersection_store(@dest.tags, @b.tags)
@dest.tags.members.sort
#=> [3, 4]

## Familia::UnsortedSet#unionstore stores union in destination
@dest.tags.delete!
result = @a.tags.unionstore(@dest.tags, @b.tags)
[result, @dest.tags.members.sort]
#=> [6, [1, 2, 3, 4, 5, 6]]

## Familia::UnsortedSet#union_store is an alias for unionstore
@dest.tags.delete!
@a.tags.union_store(@dest.tags, @b.tags)
@dest.tags.members.sort
#=> [1, 2, 3, 4, 5, 6]

## Familia::UnsortedSet#diffstore stores difference in destination
@dest.tags.delete!
result = @a.tags.diffstore(@dest.tags, @b.tags)
[result, @dest.tags.members.sort]
#=> [2, [1, 2]]

## Familia::UnsortedSet#difference_store is an alias for diffstore
@dest.tags.delete!
@a.tags.difference_store(@dest.tags, @b.tags)
@dest.tags.members.sort
#=> [1, 2]

## Familia::UnsortedSet#interstore with raw key string destination
raw_dest_key = "familia:test:raw_dest_set"
Familia.dbclient.del(raw_dest_key)
@a.tags.interstore(raw_dest_key, @b.tags)
result = Familia.dbclient.smembers(raw_dest_key).map { |v| Familia::JsonSerializer.parse(v) }.sort
Familia.dbclient.del(raw_dest_key)
result
#=> [3, 4]

# Teardown: Clean up test data
@a.tags.delete!
@b.tags.delete!
@c.tags.delete!
@dest.tags.delete!
