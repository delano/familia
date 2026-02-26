# try/features/dirty_tracking_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class DirtyTrackUser < Familia::Horreum
  identifier_field :email
  field :email
  field :name
  field :age
  field :active
end

@user = DirtyTrackUser.new(email: 'alice@example.com', name: 'Alice', age: 30, active: true)

## Freshly constructed object is not dirty
@user.dirty?
#=> false

## dirty_fields returns empty array on clean object
@user.dirty_fields
#=> []

## changed_fields returns empty hash on clean object
@user.changed_fields
#=> {}

## Assigning a field marks the object as dirty
@user.name = 'Bob'
@user.dirty?
#=> true

## dirty? with specific field name returns true for changed field
@user.dirty?(:name)
#=> true

## dirty? with unchanged field returns false
@user.dirty?(:email)
#=> false

## dirty_fields lists only changed fields
@user.dirty_fields
#=> [:name]

## changed_fields returns old and new values
@user.changed_fields[:name]
#=> ['Alice', 'Bob']

## Changing multiple fields tracks all of them
@user.age = 31
@user.dirty_fields.sort
#=> [:age, :name]

## changed_fields shows both changes
@user.changed_fields[:age]
#=> [30, 31]

## Multiple mutations to same field preserve original baseline
@user.name = 'Charlie'
@user.changed_fields[:name]
#=> ['Alice', 'Charlie']

## clear_dirty! resets all tracking state
@user.clear_dirty!
@user.dirty?
#=> false

## After clearing, dirty_fields is empty
@user.dirty_fields
#=> []

## After clearing, changed_fields is empty
@user.changed_fields
#=> {}

## Setting a field to same value still marks dirty (no equality check)
@user.name = 'Charlie'
@user.dirty?(:name)
#=> true

## clear_dirty! and start fresh for next tests
@user.clear_dirty!
@user.dirty?
#=> false

## Setting a field to nil marks it dirty
@user.active = nil
@user.dirty?(:active)
#=> true

## changed_fields shows old value and nil
@user.changed_fields[:active]
#=> [true, nil]

## Setting a field to false marks it dirty
@user.clear_dirty!
@user.age = false
@user.dirty?(:age)
#=> true

## changed_fields tracks false correctly
@user.changed_fields[:age]
#=> [31, false]

## Accepts string field names for dirty? check
@user.clear_dirty!
@user.name = 'Diana'
@user.dirty?('name')
#=> true

## Save clears dirty state
@user2 = DirtyTrackUser.new(email: 'save-test@example.com', name: 'SaveTest')
@user2.save
@user2.name = 'Changed'
@user2.dirty?
#=> true

## After save, dirty state is cleared
@user2.save
@user2.dirty?
#=> false

## Second save with new name to test refresh
@user2.name = 'Saved Again'
@user2.save
@user2.dirty?
#=> false

## refresh! clears dirty state
@user2.name = 'Unsaved Change'
@user2.dirty?
#=> true

## After refresh!, dirty state is cleared
@user2.refresh!
@user2.dirty?
#=> false

## After refresh!, name reverts to last saved value
@user2.name
#=> 'Saved Again'

## Identifier field is trackable too
@user3 = DirtyTrackUser.new(email: 'id-track@example.com', name: 'IDTrack')
@user3.save
@user3.clear_dirty!
@user3.email = 'new-id@example.com'
@user3.dirty?(:email)
#=> true

# Write-path dirty clearing tests
# Each test starts from a saved (clean) object, modifies a field via the
# normal setter (making the object dirty), then calls a specific write
# method and asserts that dirty state is cleared afterward.

## batch_update clears dirty state after successful write
@wp = DirtyTrackUser.new(email: 'write-path@example.com', name: 'WritePath', age: 25, active: true)
@wp.save
@wp.clear_dirty!
@wp.name = 'BatchUpdated'
@wp.batch_update(name: 'BatchUpdated')
@wp.dirty?
#=> false

## batch_fast_write clears dirty state after successful write
@wp.name = 'FastWritten'
@wp.batch_fast_write(name: 'FastWritten')
@wp.dirty?
#=> false

## save_fields clears dirty state after successful write
@wp.age = 99
@wp.save_fields(:age)
@wp.dirty?
#=> false

## fast writer clears dirty state for written field
@wp.name = 'FastBang'
@wp.name!('FastBang')
@wp.dirty?
#=> false

## Teardown
DirtyTrackUser.instances.members.each do |id|
  obj = DirtyTrackUser.new(id)
  obj.destroy! rescue nil
end
