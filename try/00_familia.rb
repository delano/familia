
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
  hash   :props
  string :msg
end

## Redis Objects are unique per instance of a Familia class
@a = Bone.new 'atoken'
@b = Bone.new 'btoken'
@a.owners.rediskey == @b.owners.rediskey
#=> false

## Familia::List#push
ret = @a.owners.push :value1
ret.class
#=> Familia::Object::List

## Familia::List#<<
ret = @a.owners << :value2 << :value3 << :value4
ret.class
#=> Familia::Object::List

## Familia::List#pop
@a.owners.pop
#=> 'value4'

## Familia::List#first
@a.owners.first
#=> 'value1'

## Familia::List#last
@a.owners.last
#=> 'value3'

## Familia::List#size
@a.owners.size
#=> 3


@a.owners.destroy!
