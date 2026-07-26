# try/bug_fixes/class_destroy_index_cleanup_try.rb
#
# frozen_string_literal: true

# Regression: the instance method `obj.destroy!` cleans class-level unique-index
# entries (via remove_from_class_indexes!), but the class method
# `Model.destroy!(id)` did NOT -- it only deleted the hash, related fields, and
# the instances entry. That left the unique index pointing at a now-deleted
# record, so `find_by_<field>(old_value)` resolved to a tombstone.

require_relative '../support/helpers/test_helpers'

class ::DestroyIdxUser < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :uid
  field :uid
  field :email

  unique_index :email, :email_lookup
end

@u = DestroyIdxUser.new(uid: 'du1', email: 'del@example.com')
@u.save

## sanity: the unique index resolves the record before destroy
DestroyIdxUser.find_by_email('del@example.com')&.uid
#=> "du1"

## class-level destroy! removes the object hash
DestroyIdxUser.destroy!('du1')
DestroyIdxUser.exists?('du1')
#=> false

## the index hashkey no longer maps the stale value to the dead id
DestroyIdxUser.email_lookup.get('del@example.com')
#=> nil

## find_by_<field> on the old value returns nil (no tombstone)
DestroyIdxUser.find_by_email('del@example.com')
#=> nil

## the freed email can be reused by a new record (orphan would block this)
@u2 = DestroyIdxUser.new(uid: 'du2', email: 'del@example.com')
@u2.save
DestroyIdxUser.find_by_email('del@example.com')&.uid
#=> "du2"

DestroyIdxUser.destroy!('du2')
