# try/unit/data_types/max_length_try.rb
#
# frozen_string_literal: true

# Capped collections via :max_length (issue #351).
#
# SortedSet: retains the max_length HIGHEST-scoring members (trim is
# ZREMRANGEBYRANK 0 -(N+1)) on every member-creating path: add (covering
# the shovel and []= operators), update/merge!, increment/decrement.
# ListKey: per-end semantics — push keeps the tail-N, unshift keeps the head-N.
# Validation: max_length must be a positive Integer and is rejected on
# non-implementing types; the old :maxlength spelling warns and is ignored.

require_relative '../../support/helpers/test_helpers'

require 'stringio'

class CappedBone < Familia::Horreum
  identifier_field :token
  field :token
  zset :events, max_length: 3
  list :recent, max_length: 3
end

@cb = CappedBone.new 'maxlen-token'
@zs = Familia::SortedSet.new 'test:maxlen:zs', max_length: 3
@zi = Familia::SortedSet.new 'test:maxlen:zi', max_length: 3
@zb = Familia::SortedSet.new 'test:maxlen:zb', max_length: 3
@push_list = Familia::ListKey.new 'test:maxlen:push', max_length: 3
@unshift_list = Familia::ListKey.new 'test:maxlen:unshift', max_length: 3
@bulk_list = Familia::ListKey.new 'test:maxlen:bulk', max_length: 3
@xlist = Familia::ListKey.new 'test:maxlen:x', max_length: 3
@one_list = Familia::ListKey.new 'test:maxlen:one', max_length: 1
@one_zs = Familia::SortedSet.new 'test:maxlen:onezs', max_length: 1
@zd = Familia::SortedSet.new 'test:maxlen:zd', max_length: 3
@zp = Familia::SortedSet.new 'test:maxlen:zp', max_length: 3

## Standalone SortedSet: add beyond cap keeps the 3 highest-scoring members
@zs.add('a', 1)
@zs.add('b', 2)
@zs.add('c', 3)
@zs.add('d', 4)
@zs.add('e', 5)
@zs.members
#=> ['c', 'd', 'e']

## Adding a LOW-scoring member to a full set evicts it (below the top-3)
@zs.add('low', 0)
@zs.members
#=> ['c', 'd', 'e']

## []= path is capped too (goes through add)
@zs['f'] = 6
@zs.members
#=> ['d', 'e', 'f']

## << path (timestamp scores) never grows past the cap
5.times { |i| @zs << "shovel#{i}" }
@zs.size
#=> 3

## update/merge! bulk-populating past the cap in one ZADD still trims to top-3
@zb.update('m1' => 10, 'm2' => 20, 'm3' => 30, 'm4' => 40, 'm5' => 50, 'm6' => 60)
@zb.members
#=> ['m4', 'm5', 'm6']

## merge! adding a mid-scoring member into a full set evicts the lowest
@zb['m45'] = 45
@zb.members
#=> ['m45', 'm5', 'm6']

## increment creating an absent member is a capped path (ZINCRBY + trim)
@zi.update('x1' => 100, 'x2' => 200, 'x3' => 300)
@zi.increment('newcomer', 250)
@zi.members
#=> ['x2', 'newcomer', 'x3']

## increment on an existing member does not grow the set
@zi.increment('x3', 1)
@zi.size
#=> 3

## Horreum-declared capped zset works (sorted_set :events, max_length: 3)
6.times { |i| @cb.events.add("ev#{i}", i) }
@cb.events.members
#=> ['ev3', 'ev4', 'ev5']

## Capped add inside a Horreum transaction: no nesting error, cap holds after exec
@cb.events.delete!
@cb.transaction do |_conn|
  5.times { |i| @cb.events.add("tx#{i}", i) }
end
@cb.events.members
#=> ['tx2', 'tx3', 'tx4']

## ListKey push keeps the tail-N (newest 3 of 5)
%w[p1 p2 p3 p4 p5].each { |v| @push_list.push(v) }
@push_list.to_a
#=> ['p3', 'p4', 'p5']

## ListKey unshift keeps the head-N (per-end semantics, not unified with push)
%w[u1 u2 u3 u4 u5].each { |v| @unshift_list.unshift(v) }
@unshift_list.to_a
#=> ['u5', 'u4', 'u3']

## Horreum-declared capped list caps via push too
5.times { |i| @cb.recent.push("r#{i}") }
@cb.recent.to_a
#=> ['r2', 'r3', 'r4']

## Bulk push of more values than the cap in ONE call trims to the tail-N
@bulk_list.push('b1', 'b2', 'b3', 'b4', 'b5')
@bulk_list.to_a
#=> ['b3', 'b4', 'b5']

## pushx is NOT capped (documented): it appends to an existing list untrimmed
@xlist.push('x1')
@xlist.pushx('x2', 'x3', 'x4')
@xlist.to_a
#=> ['x1', 'x2', 'x3', 'x4']

## unshiftx is NOT capped either
@xlist.unshiftx('x0')
@xlist.to_a
#=> ['x0', 'x1', 'x2', 'x3', 'x4']

## max_length: 1 on a list keeps exactly the newest element (no off-by-one)
%w[o1 o2 o3].each { |v| @one_list.push(v) }
@one_list.to_a
#=> ['o3']

## max_length: 1 on a sorted set keeps exactly the highest-scoring member
@one_zs.update('s1' => 1, 's2' => 2, 's3' => 3)
@one_zs.members
#=> ['s3']

## decrement creating an absent member is capped via the increment delegation
@zd.update('d1' => 100, 'd2' => 200, 'd3' => 300)
@zd.decrement('sinker', 50)
@zd.members
#=> ['d1', 'd2', 'd3']

## decrement creating a member that ranks in-cap evicts the lowest
@zd.decrement('d250', -250)
@zd.members
#=> ['d2', 'd250', 'd3']

## Capped writes inside a pipeline issue bare commands and the cap still holds
@cb.pipelined do |_conn|
  5.times { |i| @zp.add("pl#{i}", i) }
end
@zp.members
#=> ['pl2', 'pl3', 'pl4']

## max_length: 0 raises ArgumentError (would delete everything on every write)
begin
  Familia::SortedSet.new 'test:maxlen:zero', max_length: 0
  :no_error
rescue ArgumentError => e
  e.message.include?('positive Integer')
end
#=> true

## max_length: non-Integer raises ArgumentError
begin
  Familia::ListKey.new 'test:maxlen:str', max_length: 'x'
  :no_error
rescue ArgumentError => e
  e.message.include?('positive Integer')
end
#=> true

## max_length: negative raises ArgumentError
begin
  Familia::SortedSet.new 'test:maxlen:neg', max_length: -5
  :no_error
rescue ArgumentError => e
  e.message.include?('positive Integer')
end
#=> true

## max_length: on HashKey raises (not silently ignored)
begin
  Familia::HashKey.new 'test:maxlen:hash', max_length: 5
  :no_error
rescue ArgumentError => e
  e.class
end
#=> ArgumentError

## max_length: on UnsortedSet raises
begin
  Familia::UnsortedSet.new 'test:maxlen:set', max_length: 5
  :no_error
rescue ArgumentError => e
  e.class
end
#=> ArgumentError

## max_length: on StringKey raises
begin
  Familia::StringKey.new 'test:maxlen:string', max_length: 5
  :no_error
rescue ArgumentError => e
  e.class
end
#=> ArgumentError

## Old :maxlength spelling emits a rename warning at definition time
@warn_io = StringIO.new
@orig_logger = Familia.logger
Familia.logger = Logger.new(@warn_io)
@legacy_list = Familia::ListKey.new 'test:maxlen:legacy', maxlength: 2
Familia.logger = @orig_logger
@warn_io.string.include?(':maxlength is ignored; rename to max_length:')
#=> true

## :maxlength is ignored, never honored as an alias: list stays untrimmed
%w[l1 l2 l3 l4].each { |v| @legacy_list.push(v) }
@legacy_list.to_a
#=> ['l1', 'l2', 'l3', 'l4']

@zs.delete!
@zi.delete!
@zb.delete!
@push_list.delete!
@unshift_list.delete!
@bulk_list.delete!
@xlist.delete!
@one_list.delete!
@one_zs.delete!
@zd.delete!
@zp.delete!
@legacy_list.delete!
@cb.events.delete!
@cb.recent.delete!
@cb.destroy!
