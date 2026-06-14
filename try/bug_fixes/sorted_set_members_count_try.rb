# try/bug_fixes/sorted_set_members_count_try.rb
#
# frozen_string_literal: true

# Regression: SortedSet#members(n) / #revmembers(n) returned one fewer element
# than requested because both #members and #membersraw decremented the count
# (double-decrement). ListKey#members does not have this bug. A positive count
# is a "give me N elements" request, so members(5) must return 5 elements.

require_relative '../support/helpers/test_helpers'

@zset = Familia::SortedSet.new('bug_fixes:zset:members_count')
@zset.delete!
(1..10).each { |i| @zset.add("m#{i.to_s.rjust(2, '0')}", i.to_f) }

## members(n) returns exactly n elements (not n-1)
@zset.members(5).size
#=> 5

## membersraw(n) returns exactly n elements (not n-1)
@zset.membersraw(3).size
#=> 3

## revmembers(n) returns exactly n elements (not n-1)
@zset.revmembers(4).size
#=> 4

## members(1) returns exactly 1 element (the lowest-scored)
@zset.members(1)
#=> ["m01"]

## members with no argument returns all elements
@zset.members.size
#=> 10

## members(n) returns the n lowest-scored members in order
@zset.members(3)
#=> ["m01", "m02", "m03"]

@zset.delete!
