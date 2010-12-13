
require 'familia'
require 'storable'

Familia.apiversion = 'v1'
class ::Bone < Storable
  include Familia
  field :token
  field :name
  def index
    [token, name].join(':')
  end
  list   :owners
  set    :tags
  zset   :metrics
  hash   :props
  string :msg
end

## Redis Objects are unique per instance of a Familia class
@a = Bone.new 'atoken'
@b = Bone.new 'btoken'
@a.owners.rediskey == @b.owners.rediskey
#=> false

## Familia::Object::List#push
ret = @a.owners.push :value1
ret.class
#=> Familia::Object::List

## Familia::Object::List#<<
ret = @a.owners << :value2 << :value3 << :value4
ret.class
#=> Familia::Object::List

## Familia::Object::List#pop
@a.owners.pop
#=> 'value4'

## Familia::Object::List#first
@a.owners.first
#=> 'value1'

## Familia::Object::List#last
@a.owners.last
#=> 'value3'

## Familia::Object::List#to_a
@a.owners.to_a
#=> ['value1','value2','value3']

## Familia::Object::List#delete
@a.owners.delete 'value3'
#=> 1

## Familia::Object::List#size
@a.owners.size
#=> 2

## Familia::Object::Set#add
ret = @a.tags.add :a
ret.class
#=> Familia::Object::Set

## Familia::Object::Set#<<
ret = @a.tags << :a << :b << :c
ret.class
#=> Familia::Object::Set

## Familia::Object::Set#members
@a.tags.members.sort
#=> ['a', 'b', 'c']

## Familia::Object::Set#member? knows when a value exists
@a.tags.member? :a
#=> true

## Familia::Object::Set#member? knows when a value doesn't exist
@a.tags.member? :x
#=> false

## Familia::Object::Set#member? knows when a value doesn't exist
@a.tags.size
#=> 3

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



@a.owners.destroy!
@a.tags.destroy!
@a.metrics.destroy!
