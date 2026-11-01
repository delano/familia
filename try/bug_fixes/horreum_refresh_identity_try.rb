# try/bug_fixes/horreum_refresh_identity_try.rb
#
# frozen_string_literal: true

# Horreum#refresh! assigns every stored field and sets the persistent fields
# the stored hash lacks to nil (see
# try/bug_fixes/horreum_refresh_absent_fields_try.rb). Two kinds of stored
# hash can then give the object another identity, with dirty tracking
# cleared:
#
# - a stored identifier field that differs from the key it is stored under
#   (a raw HSET, a migration or another writer). refresh! assigned it, and
#   a later save wrote this object's fields into the other record.
# - a hash that lacks a field a Proc identifier reads. Setting that field
#   to nil leaves no identifier, or with feature :object_identifier
#   generates a new objid, and a later save would create a second record.
#   Before absent fields were set to nil, refresh! kept the in-memory value
#   and the identity did not change.
#
# refresh! now computes the identifier again after the assignment. If there
# is none, or it names a key other than the one read, it raises
# Familia::IdentifierMismatchError and leaves the object as it was, so a
# later save writes to the key the object had.

require_relative '../support/helpers/test_helpers'

# Models and helpers for this file.
module RefreshIdentityTry
  # Identifier held in a plain Symbol field.
  class Account < Familia::Horreum
    prefix :refresh_identity_account
    identifier_field :email
    field :email
    field :name
  end

  # Identifier computed by a Proc from the lazily generated objid.
  class Document < Familia::Horreum
    prefix :refresh_identity_document
    feature :object_identifier
    identifier_field ->(record) { record.objid }
    field :title
  end

  # Identifier computed by a Proc from a persistent field.
  class Member < Familia::Horreum
    prefix :refresh_identity_member
    identifier_field ->(record) { record.handle&.downcase }
    field :handle
    field :bio
  end

  # Identifier held in the objid field, which has a lookup hash.
  class Badge < Familia::Horreum
    prefix :refresh_identity_badge
    feature :object_identifier
    identifier_field :objid
    field :label
  end

  # Identifier computed by a Proc that calls a method on a persistent field
  # without a nil guard.
  class Handle < Familia::Horreum
    prefix :refresh_identity_handle
    identifier_field ->(record) { record.name.downcase }
    field :name
    field :note
  end

  # Identifier held in a field whose stored value is an Integer.
  class Ticket < Familia::Horreum
    prefix :refresh_identity_ticket
    identifier_field :num
    field :num
    field :subject
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

  # The object hash keys stored for a model.
  def self.object_keys(model)
    model.dbclient.scan_each(match: "#{model.prefix}:*:object").to_a.sort
  end
end

@raw = Familia.dbclient

RefreshIdentityTry::Account.new(email: 'a@example.com', name: 'Alice').save
RefreshIdentityTry::Account.new(email: 'b@example.com', name: 'Bob').save
@alice_key = RefreshIdentityTry::Account.dbkey('a@example.com')
@bob_key = RefreshIdentityTry::Account.dbkey('b@example.com')
# Another writer stores Bob's email in Alice's hash.
@raw.hset(@alice_key, 'email', '"b@example.com"')

## a stored identifier field that differs from the key raises IdentifierMismatchError
@account = RefreshIdentityTry::Account.new(email: 'a@example.com', name: 'Alice')
@account.name = 'edited'
@account_ivars = RefreshIdentityTry.ivars(@account)
@account_changed = @account.changed_fields
begin
  @account.refresh!
  :no_error
rescue Familia::IdentifierMismatchError => e
  [e.key, e.resolved_key]
end
#=> [@alice_key, @bob_key]

## the object keeps its identifier, key and field values
[@account.email, @account.dbkey, @account.name]
#=> ['a@example.com', @alice_key, 'edited']

## the object keeps its dirty tracking and instance variables
[@account.changed_fields == @account_changed, RefreshIdentityTry.same_ivars?(@account, @account_ivars)]
#=> [true, true]

## the chainable refresh raises the same error
@account.refresh
#=!> Familia::IdentifierMismatchError

## a save afterwards writes to the object's own key and leaves the other record alone
@account.save
[
  @raw.hget(@alice_key, 'name'),
  @raw.hget(@alice_key, 'email'),
  @raw.hgetall(@bob_key),
  RefreshIdentityTry.object_keys(RefreshIdentityTry::Account).size,
]
#=> ['"edited"', '"a@example.com"', { 'email' => '"b@example.com"', 'name' => '"Bob"' }, 2]

## a Proc identifier over objid whose objid is missing from the stored hash raises
@doc = RefreshIdentityTry::Document.new(title: 't1')
@doc_objid = @doc.objid
@doc.save
@doc_key = @doc.dbkey
@raw.hdel(@doc_key, 'objid')
@doc.title = 'edited'
@doc_ivars = RefreshIdentityTry.ivars(@doc)
@doc_changed = @doc.changed_fields
begin
  @doc.refresh!
  :no_error
rescue Familia::IdentifierMismatchError => e
  [e.key == @doc_key, e.resolved_key.nil?, e.resolved_key == @doc_key]
end
#=> [true, false, false]

## the object keeps its objid, key, field values, dirty tracking and instance variables
[
  @doc.objid == @doc_objid,
  @doc.dbkey == @doc_key,
  @doc.title,
  @doc.changed_fields == @doc_changed,
  RefreshIdentityTry.same_ivars?(@doc, @doc_ivars),
]
#=> [true, true, 'edited', true, true]

## a save afterwards updates the original record and creates no second one
@doc.save
[
  RefreshIdentityTry.object_keys(RefreshIdentityTry::Document) == [@doc_key],
  @raw.hget(@doc_key, 'title'),
]
#=> [true, '"edited"']

## a Proc identifier whose field is missing from the stored hash raises with no resolved key
@member = RefreshIdentityTry::Member.new(handle: 'Ada', bio: 'stored')
@member.save
@member_key = @member.dbkey
@raw.hdel(@member_key, 'handle')
@member_ivars = RefreshIdentityTry.ivars(@member)
begin
  @member.refresh!
  :no_error
rescue Familia::IdentifierMismatchError => e
  [e.key == @member_key, e.resolved_key]
end
#=> [true, nil]

## the object keeps the field its identifier reads
[@member.handle, @member.dbkey == @member_key, RefreshIdentityTry.same_ivars?(@member, @member_ivars)]
#=> ['Ada', true, true]

## a Proc identifier that raises on a field missing from the stored hash raises IdentifierMismatchError
@handle = RefreshIdentityTry::Handle.new(name: 'Grace', note: 'stored')
@handle.save
@handle_key = @handle.dbkey
@raw.hdel(@handle_key, 'name')
@handle_ivars = RefreshIdentityTry.ivars(@handle)
begin
  @handle.refresh!
  :no_error
rescue Familia::IdentifierMismatchError => e
  [e.key == @handle_key, e.resolved_key, e.cause.class]
end
#=> [true, nil, NoMethodError]

## the object keeps the field its identifier reads
[@handle.name, @handle.dbkey == @handle_key, RefreshIdentityTry.same_ivars?(@handle, @handle_ivars)]
#=> ['Grace', true, true]

## a stored objid identifier field that differs from the key raises IdentifierMismatchError
@badge = RefreshIdentityTry::Badge.new(label: 'stored')
@badge.save
@badge_objid = @badge.objid
@badge_key = @badge.dbkey
@raw.hset(@badge_key, 'objid', '"someone-else"')
@badge = RefreshIdentityTry::Badge.new(objid: @badge_objid)
@badge_ivars = RefreshIdentityTry.ivars(@badge)
begin
  @badge.refresh!
  :no_error
rescue Familia::IdentifierMismatchError => e
  [e.key == @badge_key, e.resolved_key == RefreshIdentityTry::Badge.dbkey('someone-else')]
end
#=> [true, true]

## the object keeps its objid and the lookup entry for it is still there
[
  @badge.objid == @badge_objid,
  RefreshIdentityTry.same_ivars?(@badge, @badge_ivars),
  RefreshIdentityTry::Badge.objid_lookup.key?(@badge_objid),
]
#=> [true, true, true]

## a stored Integer identifier read into an object holding the same digits as a String names the same key
RefreshIdentityTry::Ticket.new(num: 42, subject: 'stored').save
@ticket = RefreshIdentityTry::Ticket.new(num: '42')
@ticket.refresh!
[@ticket.num, @ticket.subject, @ticket.dirty?]
#=> [42, 'stored', false]

## refresh! on a record whose stored values match its key still succeeds
@account.refresh!
[@account.email, @account.name, @account.dirty?]
#=> ['a@example.com', 'edited', false]

delete_test_dbkeys(
  RefreshIdentityTry::Account,
  RefreshIdentityTry::Document,
  RefreshIdentityTry::Member,
  RefreshIdentityTry::Ticket,
  RefreshIdentityTry::Badge,
  RefreshIdentityTry::Handle,
)
