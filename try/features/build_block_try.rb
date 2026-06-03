# try/features/build_block_try.rb
#
# Tests for the class-level `build` factory block.
# See issue #279. `build` wraps `new` + `atomic_write` so that scalar fields
# and collection mutations made inside the block all commit in a single
# MULTI/EXEC at block exit. Uses create-only semantics (raises on duplicate).

require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Primary test class with one of each collection type
class BuildTestUser < Familia::Horreum
  identifier_field :email
  field :email
  field :name
  field :role
  set :tags
  list :sessions
  sorted_set :scores
  hashkey :settings
end

# Class with a cross-database collection for the CrossDatabaseError path
class BuildCrossDbUser < Familia::Horreum
  logical_database 0
  identifier_field :email
  field :email
  field :name
  list :sessions, logical_database: 5
end

# Clean slate
BuildTestUser.instances.clear
BuildTestUser.all.each(&:destroy!)
BuildCrossDbUser.instances.clear rescue nil

## build with a block persists scalars and collections atomically
@user_a = BuildTestUser.build(email: 'alice@example.com', name: 'Alice') do |u|
  u.role = 'admin'
  u.tags.add('staff')
  u.tags.add('beta')
  u.sessions.push('sess_a1')
  u.scores.add('reputation', 100.0)
  u.settings['theme'] = 'dark'
end
@reloaded_a = BuildTestUser.find_by_id('alice@example.com')
[
  @reloaded_a.name,
  @reloaded_a.role,
  @reloaded_a.tags.members.sort,
  @reloaded_a.sessions.members,
  @reloaded_a.scores.members,
  @reloaded_a.settings['theme'],
]
#=> ['Alice', 'admin', ['beta', 'staff'], ['sess_a1'], ['reputation'], 'dark']

## build returns the built instance
@user_b = BuildTestUser.build(email: 'bob@example.com', name: 'Bob') do |u|
  u.tags.add('member')
end
[@user_b.is_a?(BuildTestUser), @user_b.email, @user_b.name]
#=> [true, 'bob@example.com', 'Bob']

## build without a block degenerates to new + save
@user_c = BuildTestUser.build(email: 'carol@example.com', name: 'Carol')
@reloaded_c = BuildTestUser.find_by_id('carol@example.com')
[@user_c.is_a?(BuildTestUser), @reloaded_c.name]
#=> [true, 'Carol']

## build accepts a positional identifier argument plus a block
@user_e = BuildTestUser.build('erin@example.com') do |u|
  u.name = 'Erin'
  u.tags.add('positional')
end
@reloaded_e = BuildTestUser.find_by_id('erin@example.com')
[@reloaded_e.email, @reloaded_e.name, @reloaded_e.tags.members]
#=> ['erin@example.com', 'Erin', ['positional']]

## the built object is registered in the instances timeline
BuildTestUser.in_instances?('alice@example.com')
#=> true

## a scalar-only block still commits the scalar fields
@user_f = BuildTestUser.build(email: 'frank@example.com') do |u|
  u.name = 'Frank'
  u.role = 'viewer'
end
@reloaded_f = BuildTestUser.find_by_id('frank@example.com')
[@reloaded_f.name, @reloaded_f.role]
#=> ['Frank', 'viewer']

## an exception inside the block aborts the whole commit (nothing persists)
@build_raised = false
begin
  BuildTestUser.build(email: 'ghost@example.com', name: 'Ghost') do |u|
    u.tags.add('doomed')
    raise 'boom'
  end
rescue RuntimeError
  @build_raised = true
end
# Fresh object: neither the hash key nor the collection should exist
[@build_raised, BuildTestUser.find_by_id('ghost@example.com'), BuildTestUser.in_instances?('ghost@example.com')]
#=> [true, nil, false]

## the aborted build leaves no collection key behind (true atomicity)
## If collection writes were immediate (non-atomic), the tags SADD would have
## landed before the exception. Because build folds them into the same MULTI,
## the discarded transaction leaves the collection key absent.
@ghost_tags_key = BuildTestUser.new(email: 'ghost@example.com').tags.dbkey
Familia.dbclient.exists?(@ghost_tags_key)
#=> false

## the built instance is not dirty after a successful build
@user_h = BuildTestUser.build(email: 'heidi@example.com', name: 'Heidi') do |u|
  u.role = 'editor'
  u.tags.add('clean')
end
@user_h.dirty?
#=> false

## build raises RecordExistsError on duplicate (create-only semantics)
@user_i1 = BuildTestUser.build(email: 'ivan@example.com', name: 'Ivan First') do |u|
  u.tags.add('first')
end
@duplicate_raised = false
begin
  BuildTestUser.build(email: 'ivan@example.com', name: 'Ivan Second') do |u|
    u.tags.add('second')
  end
rescue Familia::RecordExistsError
  @duplicate_raised = true
end
@reloaded_i = BuildTestUser.find_by_id('ivan@example.com')
# Original is untouched; duplicate was rejected
[@duplicate_raised, @reloaded_i.name, @reloaded_i.tags.members]
#=> [true, 'Ivan First', ['first']]

## a clear-then-add inside the block is part of the same atomic commit
@user_j = BuildTestUser.build(email: 'judy@example.com', name: 'Judy') do |u|
  u.tags.add('temp')
  u.tags.clear
  u.tags.add('final')
end
@reloaded_j = BuildTestUser.find_by_id('judy@example.com')
@reloaded_j.tags.members
#=> ['final']

## build raises CrossDatabaseError when a related field spans databases
@cross_raised = nil
begin
  BuildCrossDbUser.build(email: 'cross@example.com', name: 'Cross') do |u|
    u.sessions.push('nope')
  end
rescue Familia::CrossDatabaseError => e
  @cross_raised = [e.field_name, e.field_database, e.horreum_database]
end
@cross_raised
#=> [:sessions, 5, 0]

# Cleanup
BuildTestUser.instances.clear
BuildTestUser.all.each(&:destroy!)
BuildCrossDbUser.instances.clear rescue nil
BuildCrossDbUser.all.each(&:destroy!) rescue nil
