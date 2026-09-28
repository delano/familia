# try/bug_fixes/horreum_refresh_absent_fields_try.rb
#
# frozen_string_literal: true

# Horreum#refresh! assigned only the fields present in the stored hash. A nil
# field is stored as an absent one, so a field another writer had cleared, or
# a value set in memory and never saved, kept its in-memory value while
# refresh! cleared dirty tracking, and a later save wrote that value back.
#
# refresh! also assigned through the setters with the old in-memory values
# still in place. The objid and extid setters remove the old value's entry
# from the class lookup hash, so a refresh could delete a lookup entry that
# another record owns.
#
# refresh! now starts every persistent field except the identifier at nil,
# as a newly loaded object starts, and then assigns what is stored.

require_relative '../support/helpers/test_helpers'

# Models for this file.
module RefreshAbsentFieldsTry
  # A plain record whose init hook assigns a default.
  class Record < Familia::Horreum
    prefix :refresh_absent_record
    identifier_field :rid
    field :rid
    field :name
    field :status

    def init
      @status ||= 'active'
    end
  end

  # A record with objid and extid lookup hashes.
  class Tracked < Familia::Horreum
    prefix :refresh_absent_tracked
    feature :object_identifier
    feature :external_identifier
    identifier_field :tid
    field :tid
    field :name
  end
end

@raw = Familia.dbclient

## a field another writer removed is nil after refresh!
@rec = RefreshAbsentFieldsTry::Record.new(rid: 'ra_removed', name: 'kept')
@rec.save
@raw.hdel(@rec.dbkey, 'name')
@rec.refresh!
@rec.name
#=> nil

## the refreshed object is clean
@rec.dirty?
#=> false

## a later save does not write the removed value back
@rec.save
@raw.hexists(@rec.dbkey, 'name')
#=> false

## fields that are stored are still loaded, and the identifier is kept
[@rec.rid, @rec.status]
#=> ['ra_removed', 'active']

## an unsaved value on a field with nothing stored is discarded
@unsaved = RefreshAbsentFieldsTry::Record.new(rid: 'ra_unsaved')
@unsaved.save
@unsaved.name = 'never saved'
@unsaved.refresh!
[@unsaved.name, @unsaved.dirty?]
#=> [nil, false]

## an init default with nothing stored becomes nil, as it is on a loaded object
@raw.hdel(@unsaved.dbkey, 'status')
@built = RefreshAbsentFieldsTry::Record.new(rid: 'ra_unsaved')
@built.refresh!
[@built.status, RefreshAbsentFieldsTry::Record.load('ra_unsaved').status]
#=> [nil, nil]

## refresh! leaves another record's objid and extid lookup entries in place
@owner = RefreshAbsentFieldsTry::Tracked.new(tid: 'ra_owner', name: 'owner')
@owner.save
@other = RefreshAbsentFieldsTry::Tracked.new(tid: 'ra_other', name: 'other')
@other.save
# An in-memory copy of ra_other built from the owner's attributes.
@copy = RefreshAbsentFieldsTry::Tracked.new(tid: 'ra_other', objid: @owner.objid, extid: @owner.extid)
@copy.refresh!
[
  RefreshAbsentFieldsTry::Tracked.objid_lookup[@owner.objid],
  RefreshAbsentFieldsTry::Tracked.extid_lookup[@owner.extid],
]
#=> ['ra_owner', 'ra_owner']

## the copy now carries ra_other's stored identifiers
[@copy.objid == @other.objid, @copy.extid == @other.extid]
#=> [true, true]

delete_test_dbkeys(RefreshAbsentFieldsTry::Record, RefreshAbsentFieldsTry::Tracked)
