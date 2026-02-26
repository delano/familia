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

# Known bug: clear_dirty! blanket-resets all dirty state
#
# Every write path calls clear_dirty! after persisting, but partial write
# paths (fast writers, save_fields, batch_update) only persist a subset of
# fields. The blanket reset incorrectly clears dirty state for fields that
# were NOT persisted, causing the object to report as clean when it still
# has unsaved changes.
#
# These tests document the correct behavior. They are expected to FAIL
# with the current implementation until clear_dirty! is fixed to only
# clear the fields that were actually written.

## Fast writer clears unrelated dirty fields (BUG: should preserve them)
# When fields A and B are both dirty and only A is fast-written,
# field B should still be marked dirty because it was not persisted.
@bug1 = DirtyTrackUser.new(email: 'bug1@example.com', name: 'Original', age: 20)
@bug1.save
@bug1.clear_dirty!
@bug1.name = 'Changed'
@bug1.age = 99
@bug1.name!('Changed')
@bug1.dirty?(:age)
#=> true

## Fast writer should leave object dirty when unwritten fields remain
@bug1.dirty?
#=> true

## Fast writer should not report written field as dirty
@bug1.dirty?(:name)
#=> false

## dirty_fields after fast writer should list only unwritten fields
@bug1.dirty_fields
#=> [:age]

## save_fields clears unrelated dirty fields (BUG: should preserve them)
# When fields A and B are both dirty and only A is saved via save_fields,
# field B should still be marked dirty because it was not persisted.
@bug2 = DirtyTrackUser.new(email: 'bug2@example.com', name: 'Original', age: 20)
@bug2.save
@bug2.clear_dirty!
@bug2.name = 'Changed'
@bug2.age = 99
@bug2.save_fields(:name)
@bug2.dirty?(:age)
#=> true

## save_fields should leave object dirty when unwritten fields remain
@bug2.dirty?
#=> true

## save_fields should not report written field as dirty
@bug2.dirty?(:name)
#=> false

## dirty_fields after save_fields should list only unwritten fields
@bug2.dirty_fields
#=> [:age]

## batch_update clears unrelated dirty fields (BUG: should preserve them)
# When fields A and B are both dirty and only A is batch-updated,
# field B should still be marked dirty because it was not persisted.
@bug3 = DirtyTrackUser.new(email: 'bug3@example.com', name: 'Original', age: 20)
@bug3.save
@bug3.clear_dirty!
@bug3.name = 'Changed'
@bug3.age = 99
@bug3.batch_update(name: 'Changed')
@bug3.dirty?(:age)
#=> true

## batch_update should leave object dirty when unwritten fields remain
@bug3.dirty?
#=> true

## batch_update should not report written field as dirty
@bug3.dirty?(:name)
#=> false

## dirty_fields after batch_update should list only unwritten fields
@bug3.dirty_fields
#=> [:age]

## dirty? returns false with unsaved changes after partial write (BUG)
# This is the high-level scenario: after any partial write, the object
# should still be dirty if any fields remain unpersisted.
@bug4 = DirtyTrackUser.new(email: 'bug4@example.com', name: 'Original', age: 20, active: true)
@bug4.save
@bug4.clear_dirty!
@bug4.name = 'NewName'
@bug4.age = 50
@bug4.active = false
@bug4.save_fields(:name, :age)
@bug4.dirty?
#=> true

## After partial write of two of three dirty fields, only unwritten field remains dirty
@bug4.dirty?(:active)
#=> true

## After partial write, written fields should not be dirty
@bug4.dirty?(:name)
#=> false

## After partial write, second written field should not be dirty either
@bug4.dirty?(:age)
#=> false

## dirty_fields after partial write should list only unwritten fields
@bug4.dirty_fields
#=> [:active]

## changed_fields after partial write should show only unwritten field changes
@bug4.changed_fields[:active]
#=> [true, false]

# P0: Direct unit tests for clear_dirty! selective API
# These test the selective signature of clear_dirty! directly,
# independent of any write path.

## clear_dirty! with one field name clears only that field
@sel = DirtyTrackUser.new(email: 'selective@example.com', name: 'Sel', age: 40, active: true)
@sel.save
@sel.clear_dirty!
@sel.name = 'NewSel'
@sel.age = 41
@sel.clear_dirty!(:name)
@sel.dirty?(:name)
#=> false

## clear_dirty! with one field name leaves other fields dirty
@sel.dirty?(:age)
#=> true

## clear_dirty! with one field name leaves object dirty overall
@sel.dirty?
#=> true

## clear_dirty! with multiple field names clears all specified
@sel.clear_dirty!
@sel.name = 'A'
@sel.age = 42
@sel.active = false
@sel.clear_dirty!(:name, :age)
@sel.dirty?(:name)
#=> false

## clear_dirty! with multiple field names leaves unspecified fields dirty
@sel.dirty?(:active)
#=> true

## clear_dirty! with all dirty field names results in clean object
@sel.clear_dirty!
@sel.name = 'B'
@sel.age = 43
@sel.clear_dirty!(:name, :age)
@sel.dirty?
#=> false

## clear_dirty! with all dirty field names yields empty dirty_fields
@sel.dirty_fields
#=> []

## clear_dirty! with nonexistent field does not crash
@sel.clear_dirty!
@sel.name = 'C'
@sel.clear_dirty!(:nonexistent_field)
@sel.dirty?(:name)
#=> true

## clear_dirty! with duplicate field names is harmless
@sel.clear_dirty!
@sel.name = 'D'
@sel.clear_dirty!(:name, :name)
@sel.dirty?(:name)
#=> false

## clear_dirty! with string field name coerces to symbol
@sel.clear_dirty!
@sel.name = 'E'
@sel.clear_dirty!('name')
@sel.dirty?(:name)
#=> false

## changed_fields after selective clear omits cleared field
@sel.clear_dirty!
@sel.name = 'F'
@sel.age = 44
@sel.clear_dirty!(:name)
@sel.changed_fields.key?(:name)
#=> false

## changed_fields after selective clear retains uncleared field
@sel.changed_fields.key?(:age)
#=> true

# P0: batch_update with ALL dirty fields clears everything

## batch_update with all dirty fields clears everything
@ba = DirtyTrackUser.new(email: 'batch-all@example.com', name: 'BA', age: 50, active: true)
@ba.save
@ba.clear_dirty!
@ba.name = 'BA2'
@ba.age = 51
@ba.batch_update(name: 'BA2', age: 51)
@ba.dirty?
#=> false

## batch_update with all dirty fields yields empty dirty_fields
@ba.dirty_fields
#=> []

# P1: batch_fast_write partial clear behavior

## batch_fast_write with subset preserves unwritten dirty field
@bfw = DirtyTrackUser.new(email: 'bfw@example.com', name: 'BFW', age: 60, active: true)
@bfw.save
@bfw.clear_dirty!
@bfw.name = 'BFW2'
@bfw.age = 61
@bfw.batch_fast_write(name: 'BFW2')
@bfw.dirty?(:age)
#=> true

## batch_fast_write with subset clears written field
@bfw.dirty?(:name)
#=> false

## batch_fast_write with subset leaves object dirty overall
@bfw.dirty?
#=> true

## batch_fast_write with all dirty fields clears everything
@bfw.clear_dirty!
@bfw.name = 'BFW3'
@bfw.age = 62
@bfw.batch_fast_write(name: 'BFW3', age: 62)
@bfw.dirty?
#=> false

# P1: commit_fields blanket clear

## commit_fields clears all dirty state
@cf = DirtyTrackUser.new(email: 'cf@example.com', name: 'CF', age: 70, active: true)
@cf.save
@cf.clear_dirty!
@cf.name = 'CF2'
@cf.age = 71
@cf.commit_fields
@cf.dirty?
#=> false

## commit_fields yields empty dirty_fields
@cf.dirty_fields
#=> []

# P1: Mixed scenarios -- partial write then full save

## Partial save_fields then full save: partial preserves unwritten dirty state
@mx = DirtyTrackUser.new(email: 'mixed@example.com', name: 'MX', age: 80, active: true)
@mx.save
@mx.clear_dirty!
@mx.name = 'MX2'
@mx.age = 81
@mx.active = false
@mx.save_fields(:name)
@mx.dirty?(:age)
#=> true

## Partial save_fields then full save: full save clears remaining dirty state
@mx.save
@mx.dirty?
#=> false

## Fast writer then full save: fast writer preserves unwritten dirty state
@mx.clear_dirty!
@mx.name = 'MX3'
@mx.age = 82
@mx.name!('MX3')
@mx.dirty?(:age)
#=> true

## Fast writer then full save: full save clears remaining dirty state
@mx.save
@mx.dirty?
#=> false

## Two sequential save_fields covering all dirty fields
@mx.clear_dirty!
@mx.name = 'MX4'
@mx.age = 83
@mx.save_fields(:name)
@mx.dirty?(:age)
#=> true

## Second save_fields clears remaining dirty field
@mx.save_fields(:age)
@mx.dirty?
#=> false

# P2: Edge cases -- clear_dirty! on clean objects

## Blanket clear_dirty! on already-clean object is a no-op
@clean = DirtyTrackUser.new(email: 'clean@example.com', name: 'Clean', age: 90, active: true)
@clean.save
@clean.clear_dirty!
@clean.clear_dirty!
@clean.dirty?
#=> false

## Selective clear_dirty! on already-clean object is a no-op
@clean.clear_dirty!(:name)
@clean.dirty?
#=> false

## Teardown
DirtyTrackUser.instances.members.each do |id|
  obj = DirtyTrackUser.new(id)
  obj.destroy! rescue nil
end
