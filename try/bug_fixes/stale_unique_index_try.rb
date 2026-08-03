# try/bug_fixes/stale_unique_index_try.rb
#
# frozen_string_literal: true

# Regression: changing the value of a unique-indexed field and saving left the
# OLD value's index entry orphaned. On save, only `add_to_class_<index>` ran
# (HSET new -> id) and nothing removed the previous value's mapping. As a result
# `find_by_<field>(old_value)` still resolved to the record (whose field had
# changed), and the freed old value could not be reused by another record
# (the unique guard saw the orphan and raised RecordExistsError).

require_relative '../support/helpers/test_helpers'

class ::StaleIdxUser < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :uid
  field :uid
  field :email

  unique_index :email, :email_lookup
end

# Deliberately declares NO index at load time: the unique_index arrives at
# runtime, after the first fast write, to exercise memo invalidation.
class ::StaleIdxLateDecl < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :uid
  field :uid
  field :handle
end

@u = StaleIdxUser.new(uid: 'su1', email: 'old@example.com')
@u.save

## sanity: the original email resolves before the change
StaleIdxUser.find_by_email('old@example.com')&.uid
#=> "su1"

## after loading, changing the indexed field, and saving, the new value resolves
@loaded = StaleIdxUser.find_by_id('su1')
@loaded.email = 'new@example.com'
@loaded.save
StaleIdxUser.find_by_email('new@example.com')&.uid
#=> "su1"

## the index hashkey no longer contains the old value (no orphan)
StaleIdxUser.email_lookup.get('old@example.com')
#=> nil

## find_by_<field>(old_value) no longer resolves to the (now-changed) record
StaleIdxUser.find_by_email('old@example.com')&.uid
#=> nil

## the freed old value can be claimed by a different record
@u2 = StaleIdxUser.new(uid: 'su2', email: 'old@example.com')
@u2.save
StaleIdxUser.find_by_email('old@example.com')&.uid
#=> "su2"

## fast writer on the indexed field maintains the index (#308)
@loaded.email!('fast@example.com')
StaleIdxUser.find_by_email('fast@example.com')&.uid
#=> "su1"

## fast writer removed the previous value's index entry (no orphan)
StaleIdxUser.email_lookup.get('new@example.com')
#=> nil

## fast writer to a value another record owns raises before the hash write
@loaded.email!('old@example.com')
#=!> Familia::RecordExistsError

## the failed fast write left the hash untouched
StaleIdxUser.find_by_id('su1').email
#=> "fast@example.com"

## the failed fast write rolled the in-memory value back
[@loaded.email, @loaded.dirty?(:email)]
#=> ["fast@example.com", false]

## fast writer on an indexed field refuses inside a transaction
@err = nil
@loaded.transaction do
  @loaded.email!('txn@example.com')
rescue Familia::IndexedFieldFastWriteError => e
  @err = e
end
[@err.class, @err.field, @err.index_name]
#=> [Familia::IndexedFieldFastWriteError, :email, :email_lookup]

## fast writer on an indexed field refuses inside a pipeline
@err = nil
@loaded.pipelined do
  @loaded.email!('pipe@example.com')
rescue Familia::IndexedFieldFastWriteError => e
  @err = e
end
[@err.class, StaleIdxUser.find_by_id('su1').email]
#=> [Familia::IndexedFieldFastWriteError, "fast@example.com"]

## fast writer as getter still works inside a transaction (read-only path)
result = nil
@loaded.transaction do
  result = @loaded.email!
end
result.is_a?(Redis::Future)
#=> true

## fast writer on an indexed field refuses for an unsaved record
@u3 = StaleIdxUser.new(uid: 'su3')
@u3.email!('unsaved@example.com')
#=!> Familia::PersistenceError

## a unique_index declared AFTER the first fast write is picked up: the
## fast-writer memo keys on the relationship count, not just the class
@late = StaleIdxLateDecl.new(uid: 'sl1')
@late.save
@late.handle!('pre-index')
StaleIdxLateDecl.unique_index :handle, :handle_lookup
@late.handle!('post-index')
StaleIdxLateDecl.find_by_handle('post-index')&.uid
#=> "sl1"

## subsequent fast writes maintain the late-declared index like any other
## (new value resolves, previous value's entry is retracted)
@late.handle!('post-index-2')
[StaleIdxLateDecl.handle_lookup.get('post-index'),
 StaleIdxLateDecl.find_by_handle('post-index-2')&.uid]
#=> [nil, "sl1"]

@u.destroy! rescue nil
@u2.destroy! rescue nil
@late.destroy! rescue nil
