
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


@a.owners.destroy!
