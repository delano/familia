
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
  list :owners
  list :tags
end

## Redis Objects are unique per instance of a Familia class
@a = Bone.new 'atoken'
@b = Bone.new 'btoken'
@a.owners.rediskey == @b.owners.rediskey
#=> false

## Familia::List#push
@a.owners.push :value1
#=> false

## Familia::List#size
@a.owners.size
#=> 1


@a.owners.destroy!
