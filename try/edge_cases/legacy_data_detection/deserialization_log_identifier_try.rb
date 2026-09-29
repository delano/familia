# try/edge_cases/legacy_data_detection/deserialization_log_identifier_try.rb
#
# frozen_string_literal: true

# A stored value that is not JSON is logged by log_deserialization_issue.
# The log entry used to compute dbkey, and so the identifier, on the object
# being hydrated. find_by_id, find_by_dbkey and load_multi deserialize every
# field on a newly allocated object before any setter runs, and
# naive_refresh deserializes before it assigns.
#
# When the identifier reads objid or extid, the lazy getter generated a new
# value there. The log entry named a key built from it, and the objid and
# extid setters then saw the generated value as the old one and sent HDEL to
# objid_lookup and extid_lookup when they assigned the stored value.
#
# The log entry no longer computes the identifier. It names the key the
# caller read, the key built from the identifier field's instance variable,
# or no dbkey.

require_relative '../../support/helpers/test_helpers'
require 'stringio'

# Models and helpers for this file.
module DeserializationLogIdentifierTry
  # Identifier computed by a Proc from the lazily generated objid.
  class ProcObjid < Familia::Horreum
    prefix :deslog_ident_proc_objid
    feature :object_identifier
    identifier_field ->(record) { "order_#{record.objid}" }
    field :name
    field :note
  end

  # Identifier held in the objid field.
  class FieldObjid < Familia::Horreum
    prefix :deslog_ident_field_objid
    feature :object_identifier
    identifier_field :objid
    field :name
    field :note
  end

  # Identifier held in the extid field, which is derived from objid.
  class FieldExtid < Familia::Horreum
    prefix :deslog_ident_field_extid
    feature :object_identifier
    feature :external_identifier
    identifier_field :extid
    field :name
    field :note
  end

  # Identifier held in a plain field.
  class Plain < Familia::Horreum
    prefix :deslog_ident_plain
    identifier_field :pid
    field :pid
    field :note
  end

  # Calls per command name sent to the server while the block runs, read
  # from INFO commandstats. The INFO calls themselves are left out.
  def self.commands_during
    before = command_calls
    yield
    command_calls.each_with_object({}) do |(name, calls), sent|
      delta = calls - before.fetch(name, 0)
      sent[name] = delta if delta.positive? && name != 'info'
    end
  end

  def self.command_calls
    Familia.dbclient.info('commandstats').transform_values { |stats| stats['calls'].to_i }
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

  # Saves a record, then stores a value that is not JSON in its note field.
  def self.saved_with_legacy_note(klass, **fields)
    record = klass.new(name: 'stored', **fields)
    record.save
    Familia.dbclient.hset(record.dbkey, 'note', 'plain-legacy')
    record
  end
end

## find_by_id with a Proc(objid) identifier loads the stored objid and sends no HDEL
@proc_rec = DeserializationLogIdentifierTry.saved_with_legacy_note(DeserializationLogIdentifierTry::ProcObjid)
@loaded = nil
@sent = DeserializationLogIdentifierTry.commands_during do
  @loaded = DeserializationLogIdentifierTry::ProcObjid.find_by_id(@proc_rec.identifier)
end
[@sent.key?('hdel'), @loaded.objid == @proc_rec.objid, @loaded.note]
#=> [false, true, 'plain-legacy']

## the Proc(objid) record's objid_lookup entry is kept
DeserializationLogIdentifierTry::ProcObjid.objid_lookup[@proc_rec.objid] == @proc_rec.identifier
#=> true

## find_by_id with identifier_field :objid loads the stored objid and sends no HDEL
@objid_rec = DeserializationLogIdentifierTry.saved_with_legacy_note(DeserializationLogIdentifierTry::FieldObjid)
@log = nil
@sent = DeserializationLogIdentifierTry.commands_during do
  @log = DeserializationLogIdentifierTry.log_during do
    @loaded = DeserializationLogIdentifierTry::FieldObjid.find_by_id(@objid_rec.objid)
  end
end
[@sent.key?('hdel'), @loaded.objid == @objid_rec.objid]
#=> [false, true]

## the log entry names the record's key or no key, not a key built from a generated objid
@log[/Legacy plain string in \S+#note \(([^)]*)\)/, 1]
#==> ['no dbkey', @objid_rec.dbkey].include?(result)

## the identifier_field :objid record's objid_lookup entry is kept
DeserializationLogIdentifierTry::FieldObjid.objid_lookup[@objid_rec.objid] == @objid_rec.objid
#=> true

## load_multi with identifier_field :objid sends no HDEL
@sent = DeserializationLogIdentifierTry.commands_during do
  @loaded = DeserializationLogIdentifierTry::FieldObjid.load_multi([@objid_rec.objid]).first
end
[@sent.key?('hdel'), @loaded.objid == @objid_rec.objid]
#=> [false, true]

## find_by_id with identifier_field :extid loads the stored ids and sends no HDEL
@extid_rec = DeserializationLogIdentifierTry.saved_with_legacy_note(DeserializationLogIdentifierTry::FieldExtid)
@sent = DeserializationLogIdentifierTry.commands_during do
  @loaded = DeserializationLogIdentifierTry::FieldExtid.find_by_id(@extid_rec.extid)
end
[@sent.key?('hdel'), @loaded.objid == @extid_rec.objid, @loaded.extid == @extid_rec.extid]
#=> [false, true, true]

## the identifier_field :extid record's lookup entries are kept
[
  DeserializationLogIdentifierTry::FieldExtid.objid_lookup[@extid_rec.objid] == @extid_rec.extid,
  DeserializationLogIdentifierTry::FieldExtid.extid_lookup[@extid_rec.extid] == @extid_rec.extid,
]
#=> [true, true]

## storage_inspect does not log a key built from a generated objid
@log = DeserializationLogIdentifierTry.log_during do
  DeserializationLogIdentifierTry::FieldObjid.storage_inspect(@objid_rec.dbkey)
end
@log[/Legacy plain string in \S+#note \(([^)]*)\)/, 1]
#==> ['no dbkey', @objid_rec.dbkey].include?(result)

## deserialize_value on a record with a plain identifier field names the record's key
@plain = DeserializationLogIdentifierTry::Plain.new(pid: 'deslog_plain')
@log = DeserializationLogIdentifierTry.log_during do
  @plain.deserialize_value('plain-legacy', field_name: :note)
end
@log[/Legacy plain string in \S+#note \(([^)]*)\)/, 1]
#=> 'deslog_ident_plain:deslog_plain:object'

## deserialize_value names the key it is given
@log = DeserializationLogIdentifierTry.log_during do
  DeserializationLogIdentifierTry::ProcObjid.allocate.deserialize_value(
    'plain-legacy', field_name: :note, dbkey: 'deslog_ident_proc_objid:given:object'
  )
end
@log[/Legacy plain string in \S+#note \(([^)]*)\)/, 1]
#=> 'deslog_ident_proc_objid:given:object'

delete_test_dbkeys(
  DeserializationLogIdentifierTry::ProcObjid,
  DeserializationLogIdentifierTry::FieldObjid,
  DeserializationLogIdentifierTry::FieldExtid,
  DeserializationLogIdentifierTry::Plain,
)
