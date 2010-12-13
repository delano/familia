require 'familia'
require 'familia/test_objects'

@a = Bone.new 'atoken', 'akey'

## Familia::Object::SortedSet#add
@a.metrics.add :metric2, 2
@a.metrics.add :metric4, 4
@a.metrics.add :metric0, 0
@a.metrics.add :metric1, 1
@a.metrics.add :metric3, 3
#=> true

## Familia::Object::SortedSet#members
@a.metrics.members
#=> ['metric0', 'metric1', 'metric2', 'metric3', 'metric4']

## Familia::Object::SortedSet#members
@a.metrics.membersrev
#=> ['metric4', 'metric3', 'metric2', 'metric1', 'metric0']

## Familia::Object::SortedSet#rank
@a.metrics.rank 'metric1'
#=> 1

## Familia::Object::SortedSet#revrank
@a.metrics.revrank 'metric1'
#=> 3

## Familia::Object::SortedSet#rangebyscore
@a.metrics.rangebyscore 1, 3
#=> ['metric1', 'metric2', 'metric3']

## Familia::Object::SortedSet#rangebyscore with a limit
@a.metrics.rangebyscore 1, 3, :limit => [0, 2]
#=> ['metric1', 'metric2']

## Familia::Object::SortedSet#increment
@a.metrics.increment 'metric4', 100
#=> 104

## Familia::Object::SortedSet#decrement
@a.metrics.decrement 'metric4', 50
#=> 54

## Familia::Object::SortedSet#score
@a.metrics.score 'metric4'
#=> 54

## Familia::Object::SortedSet#remrangebyscore
@a.metrics.remrangebyscore 3, 100
#=> 2

## Familia::Object::SortedSet#members after remrangebyscore
@a.metrics.members
#=> ['metric0', 'metric1', 'metric2']

## Familia::Object::SortedSet#remrangebyrank
@a.metrics.remrangebyrank 0, 1
#=> 2

## Familia::Object::SortedSet#members after remrangebyrank
@a.metrics.members
#=> ['metric2']

@a.metrics.destroy!