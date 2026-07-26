# try/integration/nil_field_absence_try.rb
#
# frozen_string_literal: true
#
# Nil-valued declared fields are ABSENT from the Valkey/Redis hash rather than
# stored as the JSON literal "null". Field absence is the native representation
# of "no value" in a hash, and it is what makes HSETNX/HEXISTS-based claim
# patterns work and keeps "unset" and "nil" the same observable state after a
# round trip.

require_relative '../support/helpers/test_helpers'

class NilAbsenceModel < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  field :claimed_at # nil until atomically claimed via HSETNX
  field :note
end

# Identifier derived from a NON-persistent attribute (a Proc), so every declared
# persistent field can be nil while the object still has a usable identifier.
# This exercises the degenerate "nothing to persist" path.
class ProcIdAbsenceModel < Familia::Horreum
  identifier_field ->(obj) { obj.probe_id }
  field :name
  field :note

  attr_accessor :probe_id
end

# Clean up any prior test data
begin
  existing = Familia.dbclient.keys('nilabsencemodel:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue StandardError
  # ignore cleanup errors
end

@id_counter = 0
def next_id
  @id_counter += 1
  "nil-absence-#{Familia.now.to_i}-#{@id_counter}"
end

## A nil declared field is not written to storage (HEXISTS is false)
@obj = NilAbsenceModel.new(id: next_id, name: 'has name')
@obj.save
Familia.dbclient.hexists(@obj.dbkey, 'claimed_at')
#=> false

## Only the non-nil fields are stored in the hash
@obj.hgetall.keys.sort
#=> ["id", "name"]

## to_h still reports every declared field, including the nil ones
@obj.to_h.keys.sort
#=> ["claimed_at", "id", "name", "note"]

## The nil field round-trips as nil after refresh (absent == nil)
@obj.refresh!
@obj.claimed_at
#=> nil

## HSETNX succeeds on a nil declared field -- the field is genuinely absent
@claim = NilAbsenceModel.new(id: next_id, name: 'claimant')
@claim.save
@claim.hsetnx('claimed_at', Familia.now.to_i.to_s)
#=> true

## A second HSETNX fails: the field now holds a value (first-writer-wins)
@claim.hsetnx('claimed_at', Familia.now.to_i.to_s)
#=> false

## Clearing a previously-set field to nil and saving REMOVES it from storage
@edit = NilAbsenceModel.new(id: next_id, name: 'edit me', note: 'temporary')
@edit.save
@edit.note = nil
@edit.save
Familia.dbclient.hexists(@edit.dbkey, 'note')
#=> false

## After clearing, HSETNX can claim the freed field again
@edit.hsetnx('note', 'reclaimed')
#=> true

## An object whose only non-nil field is its identifier still exists
@bare = NilAbsenceModel.new(id: next_id)
@bare.save
@bare.exists?
#=> true

## commit_fields also removes a field cleared to nil
@commit = NilAbsenceModel.new(id: next_id, name: 'keep', note: 'drop me')
@commit.save
@commit.note = nil
@commit.commit_fields
Familia.dbclient.hexists(@commit.dbkey, 'note')
#=> false

## multi_field_update with a nil value deletes the field
@mfu = NilAbsenceModel.new(id: next_id, name: 'mfu', note: 'present')
@mfu.save
@mfu.multi_field_update(note: nil)
Familia.dbclient.hexists(@mfu.dbkey, 'note')
#=> false

## save_fields with a nil value deletes the named field
@sf = NilAbsenceModel.new(id: next_id, name: 'sf', note: 'present')
@sf.save
@sf.note = nil
@sf.save_fields(:note)
Familia.dbclient.hexists(@sf.dbkey, 'note')
#=> false

## multi_field_fast_write with a nil value deletes the named field
@mffw = NilAbsenceModel.new(id: next_id, name: 'mffw', note: 'present')
@mffw.save
@mffw.multi_field_fast_write(note: nil)
Familia.dbclient.hexists(@mffw.dbkey, 'note')
#=> false

## multi_field_fast_write also clears the in-memory value
@mffw.note
#=> nil

## A Proc-identifier object with all-nil fields does not create a ghost instances entry
# Nothing is persisted (hmset no-ops), so no hash key is created; the identifier
# must NOT be registered in the instances timeline, or it would dangle -- listed
# in instances.to_a while exists? reports false and any load follows a dead ref.
@ghost = ProcIdAbsenceModel.new
@ghost.probe_id = "proc-#{Familia.now.to_i}-#{@id_counter += 1}"
@ghost.save
[@ghost.exists?, ProcIdAbsenceModel.instances.to_a.include?(@ghost.identifier)]
#=> [false, false]

## Once a Proc-identifier object has a real field value, it persists and registers normally
@ghost.name = 'now real'
@ghost.save
[@ghost.exists?, ProcIdAbsenceModel.instances.to_a.include?(@ghost.identifier)]
#=> [true, true]

## Legacy data: a field stored as the JSON literal "null" is cleaned up on save
@legacy = NilAbsenceModel.new(id: next_id, name: 'legacy')
@legacy.save
# Simulate a hash written by the pre-fix serializer, which stored nil as "null"
Familia.dbclient.hset(@legacy.dbkey, 'claimed_at', 'null')
@legacy.refresh! # deserialize_value turns "null" back into nil
@legacy.save     # the now-nil field is actively removed
Familia.dbclient.hexists(@legacy.dbkey, 'claimed_at')
#=> false

# Final cleanup
begin
  leftover = Familia.dbclient.keys('nilabsencemodel:*')
  leftover.concat(Familia.dbclient.keys('procidabsencemodel:*'))
  Familia.dbclient.del(*leftover) if leftover.any?
rescue StandardError
  # ignore cleanup errors
end
