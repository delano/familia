# try/bug_fixes/refresh_missing_key_try.rb
#
# frozen_string_literal: true

# Horreum#refresh! and HashKey#refresh! document
# `@raise [Familia::KeyNotFoundError]` when their key does not exist. Both
# guarded with `unless dbclient.exists(dbkey)`, but EXISTS returns a key
# count and 0 is truthy in Ruby, so the guard never fired. Horreum#refresh!
# returned normally, kept unsaved in-memory values and cleared dirty
# tracking. HashKey#refresh! went on to send HMSET with no field/value pairs
# and raised Redis::CommandError instead. Both now read the hash once and
# raise when the reply is empty, since a hash with no fields does not exist.
#
# The Horreum#refresh! docstring says a failed call leaves the object as it
# was: its field values, its other instance variables and its dirty
# tracking. The cases below pin all three for a missing key, on an object
# that holds an unsaved edit.

require_relative '../support/helpers/test_helpers'

class ::RefreshMissingKeyRecord < Familia::Horreum
  identifier_field :rid
  field :rid
  field :name
  field :note
  hashkey :props
end

# The object's instance variables, each with the object it holds.
def refresh_missing_key_ivars(obj)
  obj.instance_variables.to_h { |name| [name, obj.instance_variable_get(name)] }
end

# Whether obj holds exactly the instance variables in +saved+, each still
# the same object.
def refresh_missing_key_same_ivars?(obj, saved)
  obj.instance_variables.sort == saved.keys.sort &&
    saved.all? { |name, value| obj.instance_variable_get(name).equal?(value) }
end

@saved = RefreshMissingKeyRecord.new(rid: 'refresh_missing_saved', name: 'stored')
@saved.save
@saved.props['color'] = 'blue'

## Horreum#refresh! raises KeyNotFoundError for a record that was never saved
@unsaved = RefreshMissingKeyRecord.new(rid: 'refresh_missing_unsaved', name: 'in-memory')
@unsaved.note = 'unsaved edit'
@unsaved_ivars = refresh_missing_key_ivars(@unsaved)
@unsaved_changed = @unsaved.changed_fields
@unsaved.refresh!
#=!> Familia::KeyNotFoundError

## the failed refresh! leaves every field value in place
[@unsaved.rid, @unsaved.name, @unsaved.note]
#=> ['refresh_missing_unsaved', 'in-memory', 'unsaved edit']

## the failed refresh! leaves the unsaved edit marked dirty
[@unsaved.dirty?(:note), @unsaved.changed_fields == @unsaved_changed]
#=> [true, true]

## the failed refresh! adds, removes and replaces no instance variable
refresh_missing_key_same_ivars?(@unsaved, @unsaved_ivars)
#=> true

## the chainable Horreum#refresh raises the same error
@unsaved.refresh
#=!> Familia::KeyNotFoundError

## the failed refresh leaves the object as it was too
[refresh_missing_key_same_ivars?(@unsaved, @unsaved_ivars), @unsaved.changed_fields == @unsaved_changed]
#=> [true, true]

## Horreum#refresh! still reloads a record whose key exists
@saved.name = 'changed in memory'
@saved.refresh!
@saved.name
#=> 'stored'

## Horreum#refresh! raises once the saved record's key is gone
@gone = RefreshMissingKeyRecord.new(rid: 'refresh_missing_gone', name: 'short-lived')
@gone.save
@gone.delete!
@gone.name = 'edited after delete'
@gone_ivars = refresh_missing_key_ivars(@gone)
@gone_changed = @gone.changed_fields
@gone.refresh!
#=!> Familia::KeyNotFoundError

## the failed refresh! on a deleted record leaves its values, dirty tracking and instance variables as they were
[
  @gone.name,
  @gone.dirty?(:name),
  @gone.changed_fields == @gone_changed,
  refresh_missing_key_same_ivars?(@gone, @gone_ivars),
]
#=> ['edited after delete', true, true, true]

## HashKey#refresh! raises KeyNotFoundError, not Redis::CommandError, for a missing key
@unsaved.props.refresh!
#=!> Familia::KeyNotFoundError

## the chainable HashKey#refresh raises the same error
@unsaved.props.refresh
#=!> Familia::KeyNotFoundError

## HashKey#refresh! still works on a hash that exists
@saved.props.refresh!
@saved.props['color']
#=> 'blue'

## HashKey#refresh! raises once the hash's last field is removed
@saved.props.remove_field('color')
@saved.props.refresh!
#=!> Familia::KeyNotFoundError

@saved.props.delete!
@saved.destroy!
