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

@u.destroy! rescue nil
@u2.destroy! rescue nil
