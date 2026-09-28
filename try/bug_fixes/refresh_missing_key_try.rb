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

require_relative '../support/helpers/test_helpers'

class ::RefreshMissingKeyRecord < Familia::Horreum
  identifier_field :rid
  field :rid
  field :name
  hashkey :props
end

@saved = RefreshMissingKeyRecord.new(rid: 'refresh_missing_saved', name: 'stored')
@saved.save
@saved.props['color'] = 'blue'

## Horreum#refresh! raises KeyNotFoundError for a record that was never saved
@unsaved = RefreshMissingKeyRecord.new(rid: 'refresh_missing_unsaved', name: 'in-memory')
@unsaved.refresh!
#=!> Familia::KeyNotFoundError

## the failed refresh! leaves the unsaved in-memory value in place
@unsaved.name
#=> 'in-memory'

## the chainable Horreum#refresh raises the same error
@unsaved.refresh
#=!> Familia::KeyNotFoundError

## Horreum#refresh! still reloads a record whose key exists
@saved.name = 'changed in memory'
@saved.refresh!
@saved.name
#=> 'stored'

## Horreum#refresh! raises once the saved record's key is gone
@gone = RefreshMissingKeyRecord.new(rid: 'refresh_missing_gone', name: 'short-lived')
@gone.save
@gone.delete!
@gone.refresh!
#=!> Familia::KeyNotFoundError

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
