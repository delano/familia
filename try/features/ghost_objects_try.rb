# try/features/ghost_objects_try.rb
#
# frozen_string_literal: true

# Documents and verifies ghost object behavior: what happens when an
# object's hash key is deleted but its identifier remains in the
# instances sorted set. This is the scenario described in Issue 1.

require_relative '../support/helpers/test_helpers'

class GhostTestModel < Familia::Horreum
  identifier_field :gid
  field :gid
  field :name
end

# Clean up any leftover test data
begin
  existing = Familia.dbclient.keys('ghosttestmodel:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
GhostTestModel.instances.clear

## load(nonexistent_id) returns nil
GhostTestModel.load('does-not-exist')
#=> nil

## Save an object so we can test ghost behavior
@ghost_obj = GhostTestModel.new(gid: 'ghost-1', name: 'Ghost')
@ghost_obj.save
GhostTestModel.in_instances?('ghost-1')
#=> true

## The hash key exists in Redis
GhostTestModel.exists?('ghost-1')
#=> true

## Delete the hash key directly (simulates TTL expiry)
Familia.dbclient.del(@ghost_obj.dbkey)
GhostTestModel.exists?('ghost-1')
#=> false

## The identifier still lingers in instances (ghost entry)
GhostTestModel.instances.member?('ghost-1')
#=> true

## load triggers cleanup_stale_instance_entry and returns nil
GhostTestModel.load('ghost-1')
#=> nil

## After load, the ghost entry has been cleaned up
GhostTestModel.instances.member?('ghost-1')
#=> false

## load(id) where hash exists but not in instances returns the object
@unregistered = GhostTestModel.new(gid: 'unreg-1', name: 'Unregistered')
@unregistered.save
GhostTestModel.instances.remove('unreg-1')
GhostTestModel.instances.member?('unreg-1')
#=> false

## The hash key still exists
GhostTestModel.exists?('unreg-1')
#=> true

## load bypasses registry and returns the object from the hash key
@loaded = GhostTestModel.load('unreg-1')
@loaded.nil?
#=> false

## The loaded object has the correct fields
@loaded.name
#=> 'Unregistered'

## in_instances? returns false for unregistered hashes
GhostTestModel.in_instances?('unreg-1')
#=> false

## in_instances? returns true for registered objects
@registered = GhostTestModel.new(gid: 'reg-1', name: 'Registered')
@registered.save
GhostTestModel.in_instances?('reg-1')
#=> true

## in_instances? returns false for empty identifier
GhostTestModel.in_instances?('')
#=> false

## in_instances? returns false for nil identifier
GhostTestModel.in_instances?(nil)
#=> false

## instances.to_a includes ghost identifiers (not lazily cleaned)
@ghost2 = GhostTestModel.new(gid: 'ghost-2', name: 'Ghost 2')
@ghost2.save
Familia.dbclient.del(@ghost2.dbkey)
GhostTestModel.instances.member?('ghost-2')
#=> true

## Loading the ghost triggers cleanup
GhostTestModel.load('ghost-2')
GhostTestModel.instances.member?('ghost-2')
#=> false

## Teardown
begin
  existing = Familia.dbclient.keys('ghosttestmodel:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
GhostTestModel.instances.clear
