# try/horreum/relations_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test Horreum Redis type relations functionality

# Define test classes with various Redis type relationships
class RelationsTestUser < Familia::Horreum
  identifier :userid
  field :userid
  field :name
  list :sessions
  set :tags
  zset :scores
  hashkey :preferences
end

class RelationsTestProduct < Familia::Horreum
  identifier :productid
  field :productid
  field :title
  list :reviews
  set :categories
  zset :ratings
  hashkey :metadata
  counter :views
end

# Setup test objects
@test_user = RelationsTestUser.new
@test_user.userid = "user123"
@test_user.name = "Test User"

@test_product = RelationsTestProduct.new
@test_product.productid = "prod456"
@test_product.title = "Test Product"

## Class knows about Redis type relationships
RelationsTestUser.has_relations?
#=> true

## Class can list Redis type definitions
redis_types = RelationsTestUser.redis_types
redis_types.keys.sort
#=> [:preferences, :scores, :sessions, :tags]

## Redis type definitions are accessible
sessions_def = RelationsTestUser.redis_types[:sessions]
sessions_def.nil?
#=> false

## Can access different Redis type instances
sessions = @test_user.sessions
tags = @test_user.tags
scores = @test_user.scores
prefs = @test_user.preferences
[sessions.class.name, tags.class.name, scores.class.name, prefs.class.name]
#=> ["Familia::List", "Familia::Set", "Familia::SortedSet", "Familia::HashKey"]

## Redis types use correct Redis keys
sessions.rediskey
#=> "v1:relationstestuser:user123:sessions"

## Redis types use correct Redis keys
tags.rediskey
#=> "v1:relationstestuser:user123:tags"

## Can work with List Redis type
@test_user.sessions.clear
@test_user.sessions.lpush("session1", "session2")
@test_user.sessions.size
#=> 2

## Can work with Set Redis type
@test_user.tags.clear
@test_user.tags.sadd("ruby", "redis", "web")
@test_user.tags.size
#=> 3

## Can work with SortedSet Redis type
@test_user.scores.clear
@test_user.scores.zadd(100, "level1")
@test_user.scores.zadd(200, "level2")
@test_user.scores.size
#=> 2

## Can work with HashKey Redis type
@test_user.preferences.clear
@test_user.preferences.hset("theme", "dark")
@test_user.preferences.hset("lang", "en")
@test_user.preferences.size
#=> 2

## Counter Redis type works
@test_product.views.clear
@test_product.views.increment
@test_product.views.increment(5)
@test_product.views.value
#=> 6

## Redis types maintain parent reference
@test_user.sessions.parent == @test_user
#=> true

## Redis types know their field name
@test_user.tags.field
#=> :tags

## Can check if Redis types exist
@test_user.scores.zadd(50, "test")
before_exists = @test_user.scores.exists?
@test_user.scores.clear
after_exists = @test_user.scores.exists?
[before_exists, after_exists]
#=> [true, false]

## Can destroy individual Redis types
@test_user.preferences.hset("temp", "value")
@test_user.preferences.destroy
@test_user.preferences.exists?
#=> false

## Parent object destruction cleans up relations
@test_user.sessions.lpush("cleanup_test")
@test_user.destroy!
@test_user.sessions.exists?
#=> false

# Cleanup
@test_product.destroy!
