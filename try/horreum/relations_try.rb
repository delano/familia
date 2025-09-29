# try/horreum/relations_try.rb
# Test Horreum Database type relations functionality

require_relative '../helpers/test_helpers'

Familia.debug = false

class RelationsTestUser < Familia::Horreum
  prefix 'relationstestuser'
  identifier_field :userid
  field :userid
  field :name
  list :sessions
  set :tags
  zset :scores
  hashkey :preferences
end

class RelationsTestProduct < Familia::Horreum
  prefix 'relationstestproduct'
  identifier_field :productid
  field :productid
  field :title
  list :reviews
  set :categories
  zset :ratings
  hashkey :metadata
  counter :views
end

@test_user = RelationsTestUser.new
@test_user.userid = 'user123'
@test_user.name = 'Test User'

@test_product = RelationsTestProduct.new
@test_product.productid = 'prod456'
@test_product.title = 'Test Product'

## Class knows about Database type relationships
RelationsTestUser.relations?
#=> true

## Class can list Database type definitions
related_fields = RelationsTestUser.related_fields
related_fields.keys.sort
#=> [:preferences, :scores, :sessions, :tags]

## Database type definitions are accessible
sessions_def = RelationsTestUser.related_fields[:sessions]
sessions_def.nil?
#=> false

## Can access different Database type instances
sessions = @test_user.sessions
tags = @test_user.tags
scores = @test_user.scores
prefs = @test_user.preferences
[sessions.class.name, tags.class.name, scores.class.name, prefs.class.name]
#=> ["Familia::ListKey", "Familia::UnsortedSet", "Familia::SortedSet", "Familia::HashKey"]

## Database types use correct dbkeys
@test_user.sessions.dbkey
#=> "relationstestuser:user123:sessions"

## Database types use correct dbkeys
@test_user.tags.dbkey
#=> "relationstestuser:user123:tags"

## Can work with List Database type
@test_user.sessions.clear
@test_user.sessions.push('session1', 'session2')
@test_user.sessions.size
#=> 2

## Can work with UnsortedSet Database type
@test_user.tags.clear
@test_user.tags.add('ruby', 'valkey', 'web')
@test_user.tags.size
#=> 3

## Can work with SortedSet Database type
@test_user.scores.clear
@test_user.scores.add('level1', 100)
@test_user.scores.add('level2', 200)
@test_user.scores.size
#=> 2

## Can work with HashKey Database type
@test_user.preferences.clear
@test_user.preferences.put('theme', 'dark')
@test_user.preferences.put('lang', 'en')
@test_user.preferences.size
#=> 2

## Clearing a counter returns false when not set yet
@test_product.views.clear
@test_product.views.clear
#=> false

## Clearing a counter returns true when it is set
@test_product.views.increment
@test_product.views.clear
#=> true

## Counter Database type works
@test_product.views.increment
@test_product.views.incrementby(5)
@test_product.views.value
#=> 6

## Database types maintain ParentDefinition reference, not the parent itself
@test_user.sessions.parent
#=/> @test_user
#=:> Familia::Horreum::ParentDefinition

## Database types maintain ParentDefinition reference, not the parent itself
@test_user.sessions.parent
#=> Familia::Horreum::ParentDefinition.from_parent(@test_user)

## Database types know their field name
@test_user.tags.keystring
#=> :tags

## Can check if Database types exist
@test_user.scores.add('test', 50)
before_exists = @test_user.scores.exists?
@test_user.scores.clear
after_exists = @test_user.scores.exists?
[before_exists, after_exists]
#=> [true, false]

## Can destroy individual Database types
@test_user.preferences.put('temp', 'value')
@test_user.preferences.clear
@test_user.preferences.exists?
#=> false

## Parent object destruction DOES clean up relations (since v2.0.0.pre16)
@test_user.sessions.push('cleanup_test')
@test_user.destroy!
@test_user.sessions.exists?
#=> false

## If the parent instance is still in memory, can use it
## to access and clear the child field.
@test_user.sessions.add(Familia.now)
@test_user.sessions.size
#=> 1

@test_user.sessions.delete!

@test_product.destroy!
