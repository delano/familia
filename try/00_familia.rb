
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

## Test list
@a = Bone.new 'sometoken', 'somename'
@b = Bone.new 'btoken', 'bname'
p [1, @a.key]
p [1, @a.owners.rediskey]
p [1, @b.owners.rediskey]
#=> true