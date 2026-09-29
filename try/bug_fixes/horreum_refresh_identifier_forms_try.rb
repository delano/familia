# try/bug_fixes/horreum_refresh_identifier_forms_try.rb
#
# frozen_string_literal: true

# Horreum#refresh! sets every persistent field except a Symbol or String
# identifier field to nil before it assigns the stored values (see
# try/bug_fixes/horreum_refresh_absent_fields_try.rb). A Proc identifier, or
# an identifier_field naming a method, is computed from those fields, so
# nothing may compute the identifier between the reset and the assignment.
# There dbkey would raise Familia::NoIdentifier, and with a Proc that reads
# objid the lazy objid getter would generate a new value that the objid
# setter then removes from objid_lookup with HDEL. So refresh! deserializes
# the stored values before the reset, while the fields still name the key it
# read, and assigns them with initialize_with_keyword_args, not through
# naive_refresh. The cases below pin that the fields are restored, that only
# HGETALL is sent, and that the log entry for a value that is not JSON names
# the key refresh! read. Before refresh! reset the fields, it computed the
# identifier only while they were intact, and these identifier forms
# refreshed without error.
#
# naive_refresh interpolated dbkey into its debug message before assigning
# anything, even with debug logging off. It raised Familia::NoIdentifier on
# an object whose identifier was not set yet, and on an object with no objid
# yet whose Proc identifier reads objid it sent HDEL to objid_lookup. It no
# longer computes dbkey. The naive_refresh cases below pin that.

require_relative '../support/helpers/test_helpers'

# Models and helpers for this file.
module RefreshIdentifierFormsTry
  # Identifier computed by a Proc from a persistent field.
  class ProcRecord < Familia::Horreum
    prefix :refresh_idform_proc
    identifier_field ->(record) { record.email&.downcase }
    field :email
    field :name
    field :note
  end

  # Identifier named by a Symbol that is a method, not a field.
  class MethodRecord < Familia::Horreum
    prefix :refresh_idform_method
    identifier_field :scoped_id
    field :org
    field :slug
    field :note

    def scoped_id
      [org, slug].compact.join(':')
    end
  end

  # Identifier computed by a Proc from the lazily generated objid.
  class ObjidRecord < Familia::Horreum
    prefix :refresh_idform_objid
    feature :object_identifier
    identifier_field ->(record) { "order_#{record.objid}" }
    field :name
    field :note
  end

  # Identifier held in a plain Symbol field.
  class SymbolRecord < Familia::Horreum
    prefix :refresh_idform_symbol
    identifier_field :rid
    field :rid
    field :name
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
end

@raw = Familia.dbclient

## a Proc identifier over a persistent field: refresh! restores the stored fields and clears an unstored one
@proc = RefreshIdentifierFormsTry::ProcRecord.new(email: 'idform@example.com', name: 'stored')
@proc.save
@proc.name = 'unsaved'
@proc.note = 'never stored'
@proc.refresh!
[@proc.email, @proc.name, @proc.note, @proc.dirty?]
#=> ['idform@example.com', 'stored', nil, false]

## the refreshed Proc-identifier record can be saved again
@proc.name = 'renamed'
@proc.save
RefreshIdentifierFormsTry::ProcRecord.load('idform@example.com').name
#=> 'renamed'

## refresh on a Proc-identifier record returns the record
@proc.name = 'unsaved'
@proc.refresh.name
#=> 'renamed'

## an identifier_field naming a method: refresh! restores the fields it reads
@method = RefreshIdentifierFormsTry::MethodRecord.new(org: 'acme', slug: 'home')
@method.save
@method.note = 'never stored'
@method.refresh!
[@method.identifier, @method.note]
#=> ['acme:home', nil]

## a Proc identifier over objid: refresh! sends only HGETALL and keeps the objid and its lookup entry
@objid_rec = RefreshIdentifierFormsTry::ObjidRecord.new(name: 'stored')
@objid_rec.save
@objid = @objid_rec.objid
@objid_rec.note = 'never stored'
@sent = RefreshIdentifierFormsTry.commands_during { @objid_rec.refresh! }
[
  @sent,
  @objid_rec.objid == @objid,
  RefreshIdentifierFormsTry::ObjidRecord.objid_lookup[@objid] == "order_#{@objid}",
  @objid_rec.note,
]
#=> [{ 'hgetall' => 1 }, true, true, nil]

## a stored value that is not JSON is loaded and logged with the key refresh! read, and nothing is written
@raw.hset(@objid_rec.dbkey, 'note', 'plain-legacy')
@log_io = StringIO.new
@original_logger = Familia.logger
Familia.logger = Familia::FamiliaLogger.new(@log_io)
begin
  @sent = RefreshIdentifierFormsTry.commands_during { @objid_rec.refresh! }
ensure
  Familia.logger = @original_logger
end
[@sent, @objid_rec.note, @log_io.string.include?("(#{@objid_rec.dbkey})")]
#=> [{ 'hgetall' => 1 }, 'plain-legacy', true]

## naive_refresh assigns the identifier field on an object that has none yet
@naive = RefreshIdentifierFormsTry::SymbolRecord.new
@naive.naive_refresh(rid: '"idform_naive"', name: '"named"')
[@naive.rid, @naive.name]
#=> ['idform_naive', 'named']

## naive_refresh on a Proc(objid) object with no objid yet assigns the objid and sends nothing
@naive_objid = RefreshIdentifierFormsTry::ObjidRecord.allocate
@sent = RefreshIdentifierFormsTry.commands_during do
  @naive_objid.naive_refresh(objid: '"idform-naive-objid"', name: '"named"')
end
[@sent, @naive_objid.objid]
#=> [{}, 'idform-naive-objid']

delete_test_dbkeys(
  RefreshIdentifierFormsTry::ProcRecord,
  RefreshIdentifierFormsTry::MethodRecord,
  RefreshIdentifierFormsTry::ObjidRecord,
  RefreshIdentifierFormsTry::SymbolRecord,
)
