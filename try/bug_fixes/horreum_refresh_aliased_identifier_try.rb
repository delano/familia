# try/bug_fixes/horreum_refresh_aliased_identifier_try.rb
#
# frozen_string_literal: true

# Horreum#refresh! keeps a Symbol or String identifier field that the
# stored hash lacks (see try/bug_fixes/horreum_refresh_absent_fields_try.rb),
# and the log entry for a stored value that is not JSON names the key built
# from that field's instance variable (see
# try/edge_cases/legacy_data_detection/deserialization_log_identifier_try.rb).
# Both looked the identifier field up in field_types by the name
# identifier_field gives. field_types is keyed by field name, and a field
# declared with +as:+ is read through its accessor, so identifier_field
# names the accessor (field :user_id, as: :uid; identifier_field :uid).
# refresh! then cleared the field like any other, found no identifier in
# the stored values and raised Familia::IdentifierMismatchError, and the
# log entry named no dbkey. The identifier field is now found by its name
# or by its accessor method name.

require_relative '../support/helpers/test_helpers'
require 'stringio'

# Models and helpers for this file.
module RefreshAliasedIdentifierTry
  # Identifier held in a field read through an +as:+ accessor.
  class Member < Familia::Horreum
    prefix :refresh_alias_member
    identifier_field :uid
    field :user_id, as: :uid
    field :name
    field :note
  end

  # The log output written while the block runs.
  def self.log_during
    io = StringIO.new
    original = Familia.logger
    Familia.logger = Familia::FamiliaLogger.new(io)
    begin
      yield
    ensure
      Familia.logger = original
    end
    io.string
  end

  # The object's instance variables, each with the object it holds.
  def self.ivars(obj)
    obj.instance_variables.to_h { |name| [name, obj.instance_variable_get(name)] }
  end

  # Whether obj holds exactly the instance variables in +saved+, each still
  # the same object.
  def self.same_ivars?(obj, saved)
    obj.instance_variables.sort == saved.keys.sort &&
      saved.all? { |name, value| obj.instance_variable_get(name).equal?(value) }
  end
end

@raw = Familia.dbclient
@absent_key = RefreshAliasedIdentifierTry::Member.dbkey('u2')
@other_key = RefreshAliasedIdentifierTry::Member.dbkey('u4')
@foreign_key = RefreshAliasedIdentifierTry::Member.dbkey('u9')
# A hash that lacks the identifier field, and one that holds another key's
# identifier, as a raw HSET or another writer leaves them.
@raw.hset(@absent_key, 'name', '"only-name"')
@raw.hset(@other_key, 'user_id', '"u9"', 'name', '"other"')

## the field is stored under its name, and the identifier is read through its accessor
@stored = RefreshAliasedIdentifierTry::Member.new(user_id: 'u3', name: 'saved')
@stored.save
[@raw.hgetall(@stored.dbkey), @stored.identifier, @stored.dbkey]
#=> [{ 'user_id' => '"u3"', 'name' => '"saved"' }, 'u3', 'refresh_alias_member:u3:object']

## with the identifier field stored, refresh! assigns every stored field
@stored.name = 'changed'
@stored.note = 'never stored'
[@stored.refresh!, @stored.uid, @stored.name, @stored.note, @stored.dirty?]
#=> [[:user_id, :name], 'u3', 'saved', nil, false]

## with the identifier field absent from the stored hash, refresh! keeps uid and returns the loaded fields
@absent = RefreshAliasedIdentifierTry::Member.new(user_id: 'u2', name: 'stale')
@absent.note = 'never stored'
[@absent.refresh!, @absent.uid, @absent.name, @absent.note, @absent.dirty?]
#=> [[:name], 'u2', 'only-name', nil, false]

## the refreshed object still names the key that was read
@absent.dbkey
#=> @absent_key

## a stored identifier that names a different key raises IdentifierMismatchError
@other = RefreshAliasedIdentifierTry::Member.new(user_id: 'u4', name: 'mine')
@other.name = 'edited'
@other_ivars = RefreshAliasedIdentifierTry.ivars(@other)
@other_changed = @other.changed_fields
begin
  @other.refresh!
  :no_error
rescue Familia::IdentifierMismatchError => e
  [e.key, e.resolved_key]
end
#=> [@other_key, @foreign_key]

## the object keeps its identifier, key, field values and dirty tracking
[
  @other.uid,
  @other.dbkey,
  @other.name,
  @other.changed_fields == @other_changed,
  RefreshAliasedIdentifierTry.same_ivars?(@other, @other_ivars),
]
#=> ['u4', @other_key, 'edited', true, true]

## the log entry for a stored value that is not JSON names the key built from the identifier field
@log = RefreshAliasedIdentifierTry.log_during do
  RefreshAliasedIdentifierTry::Member.new(user_id: 'u5').deserialize_value('plain-legacy', field_name: :note)
end
@log[/Legacy plain string in \S+#note \(([^)]*)\)/, 1]
#=> 'refresh_alias_member:u5:object'

delete_test_dbkeys(RefreshAliasedIdentifierTry::Member)
