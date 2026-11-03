# try/integration/futures/related_field_predicates_futures_try.rb
#
# frozen_string_literal: true

# The generated related-field predicates (user.tags?, User.instances?) inside
# transaction, atomic_write and pipelined blocks. Each one tests the field's
# empty?, which returns the command's Redis::Future there, so the predicate
# passes that Future through instead of negating it. See
# docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# One related field of each kind, plus a class-level sorted set.
class FuturesPredicateOwner < Familia::Horreum
  identifier_field :oid
  field :oid
  field :name
  set :tags
  list :items
  zset :scores
  hashkey :counts
  string :note
  json_string :prefs
  class_sorted_set :board
end

delete_test_dbkeys(FuturesPredicateOwner)

@owner = FuturesPredicateOwner.new(oid: 'fpo-1', name: 'n0')
@owner.save
@owner.tags.add('a')
@owner.items.push('x')
@owner.scores.add('m', 1)
@owner.counts['k'] = 1
@owner.note.value = 'hello'
@owner.prefs.value = { 'a' => 1 }
FuturesPredicateOwner.board.add('z', 1)

@empty = FuturesPredicateOwner.new(oid: 'fpo-empty', name: 'e0')
@empty.save

@instance_predicates = lambda do |rec|
  [rec.tags?, rec.items?, rec.scores?, rec.counts?, rec.note?, rec.prefs?]
end

## outside a block: the predicates answer true for filled fields
@instance_predicates.call(@owner)
#=> [true, true, true, true, true, true]

## outside a block: the predicates answer false for empty fields
@instance_predicates.call(@empty)
#=> [false, false, false, false, false, false]

## outside a block: class-level predicates still answer
[FuturesPredicateOwner.board?, FuturesPredicateOwner.instances?]
#=> [true, true]

## inside atomic_write: instance predicates pass their Futures through and the scalar field persists
@ret = nil
@owner.atomic_write do
  @owner.name = 'aw-pred'
  @ret = @instance_predicates.call(@owner)
end
[@ret.map(&:class).uniq, FuturesPredicateOwner.load('fpo-1').name]
#=> [[Redis::Future], "aw-pred"]

## inside atomic_write: each Future resolves to what the field's empty? resolves to
@ret.map(&:value)
#=> [1, 1, 1, 1, "hello", "{\"a\":1}"]

## inside a pipeline: empty fields resolve to a zero count or nil
@ret = nil
FuturesPredicateOwner.pipelined { @ret = @instance_predicates.call(@empty) }
[@ret.map(&:class).uniq, @ret.map(&:value)]
#=> [[Redis::Future], [0, 0, 0, 0, nil, nil]]

## inside a transaction: instance predicates pass their Futures through
@ret = nil
@owner.transaction { @ret = [@owner.tags?, @empty.tags?] }
[@ret.map(&:class).uniq, @ret.map(&:value)]
#=> [[Redis::Future], [1, 0]]

## inside a pipeline: class-level predicates pass their Futures through
@ret = nil
FuturesPredicateOwner.pipelined { @ret = [FuturesPredicateOwner.board?, FuturesPredicateOwner.instances?] }
[@ret.map(&:class).uniq, @ret.map(&:value)]
#=> [[Redis::Future], [1, 2]]

## inside atomic_write: a class-level predicate passes its Future through and the scalar field persists
@ret = nil
@owner.atomic_write do
  @owner.name = 'aw-class-pred'
  @ret = FuturesPredicateOwner.board?
end
[@ret.class, @ret.value, FuturesPredicateOwner.load('fpo-1').name]
#=> [Redis::Future, 1, "aw-class-pred"]

# Teardown
delete_test_dbkeys(FuturesPredicateOwner)
