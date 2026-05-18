# try/unit/data_types/sorted_set_try.rb
#
# frozen_string_literal: true

# try/data_types/sorted_set_try.rb

require_relative '../../support/helpers/test_helpers'

@a = Bone.new 'atoken'

## Familia::SortedSet#add
@a = Bone.new 'atoken'
@a.metrics.add :metric2, 2
@a.metrics.add :metric4, 4
@a.metrics.add :metric0, 0
@a.metrics.add :metric1, 1
@a.metrics.add :metric3, 3
#=> true

## Familia::SortedSet#members
@a.metrics.members
#=> ['metric0', 'metric1', 'metric2', 'metric3', 'metric4']

## Familia::SortedSet#members
@a.metrics.revmembers
#=> ['metric4', 'metric3', 'metric2', 'metric1', 'metric0']

## Familia::SortedSet#rank
@a.metrics.rank 'metric1'
#=> 1

## Familia::SortedSet#revrank
@a.metrics.revrank 'metric1'
#=> 3

## Familia::SortedSet#rangebyscore
@a.metrics.rangebyscore 1, 3
#=> ['metric1', 'metric2', 'metric3']

## Familia::SortedSet#rangebyscore with a limit
@a.metrics.rangebyscore 1, 3, limit: [0, 2]
#=> ['metric1', 'metric2']

## Familia::SortedSet#increment
@a.metrics.increment 'metric4', 100
#=> 104

## Familia::SortedSet#decrement
@a.metrics.decrement 'metric4', 50
#=> 54

## Familia::SortedSet#score
@a.metrics.score 'metric4'
#=> 54.0

## Familia::SortedSet#remrangebyscore
@a.metrics.remrangebyscore 3, 100
#=> 2

## Familia::SortedSet#members after remrangebyscore
@a.metrics.members
#=> ['metric0', 'metric1', 'metric2']

## Familia::SortedSet#remrangebyrank
@a.metrics.remrangebyrank 0, 1
#=> 2

## Familia::SortedSet#members after remrangebyrank
@a.metrics.members
#=> ['metric2']

## Familia::SortedSet#update bulk-adds a Hash of member => score in one ZADD, returns new count
@u = Bone.new 'zset_bulk_update'
@u.metrics.update(alpha: 1, gamma: 3, beta: 2)
#=> 3

## Familia::SortedSet#update orders members by their given scores
@u.metrics.members
#=> ['alpha', 'beta', 'gamma']

## Familia::SortedSet#merge! is an alias and updates existing scores (0 new members)
@u.metrics.merge!(alpha: 10)
#=> 0

## Familia::SortedSet#merge! re-scored member moves position
@u.metrics.members
#=> ['beta', 'gamma', 'alpha']

## Familia::SortedSet#update with empty Hash is a no-op returning 0
@u.metrics.update({})
#=> 0

## Familia::SortedSet#update raises ArgumentError on non-Hash argument
begin
  @u.metrics.update([:not, :a, :hash])
  :no_error
rescue ArgumentError => e
  e.message
end
#=> 'Argument to bulk add must be a hash'

## Familia::SortedSet#update raises a clear ArgumentError on a non-Numeric score (not auto-defaulted like #add)
begin
  @u.metrics.update('alice' => 1000, 'bob' => nil)
  :no_error
rescue ArgumentError => e
  e.message
end
#=> 'SortedSet#update score for "bob" must be Numeric, got NilClass'

## Familia::SortedSet#update rejects a bad score before issuing the ZADD (alice not added)
@u.metrics.member?('alice')
#=> false

@u.metrics.delete!
@a.metrics.delete!
