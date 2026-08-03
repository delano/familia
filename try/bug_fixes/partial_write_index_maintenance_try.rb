# try/bug_fixes/partial_write_index_maintenance_try.rb
#
# frozen_string_literal: true

# Regression coverage for #308: partial writers (commit_fields, save_fields,
# multi_field_update) used to write the object hash and clear dirty tracking
# without touching class-level indexes, leaving unique_index lookups stale.
# They now guard and claim unique indexes BEFORE their transaction opens
# (fail-closed, ADR-0002) and maintain the index entries inside the same
# MULTI as the hash write. multi_field_fast_write cannot claim (one-HMSET
# contract), so it refuses indexed fields outright with
# Familia::IndexedFieldFastWriteError instead of writing a stale hash.

require_relative '../support/helpers/test_helpers'

class ::PartialIdxUser < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :uid
  field :uid
  field :email
  field :nickname

  unique_index :email, :email_lookup
end

class ::PartialIdxBucket < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :custid
  field :custid
  field :status

  multi_index :status, :status_index
end

# Two unique indexes, so a fast write can offend on more than one field at
# once (the error must name them all, not just the first).
class ::PartialIdxDouble < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :did
  field :did
  field :email
  field :username
  field :note

  unique_index :email, :em_lookup
  unique_index :username, :un_lookup
end

# objid's setter has a Redis side effect (objid_lookup HDEL) that the
# multi_field_update rollback cannot restore -- the field must be refused.
class ::PartialIdxOwner < Familia::Horreum
  feature :object_identifier

  identifier_field :pid
  field :pid
  field :label
end

cleanup_keys = Familia.dbclient.keys('partial_idx_user:*') +
               Familia.dbclient.keys('partial_idx_bucket:*') +
               Familia.dbclient.keys('partial_idx_double:*') +
               Familia.dbclient.keys('partial_idx_owner:*')
Familia.dbclient.del(*cleanup_keys) if cleanup_keys.any?

def hmset_calls
  Familia.dbclient.info('commandstats').dig('hmset', 'calls').to_i
end

# =============================================
# 1. Partial writers maintain unique indexes
# =============================================

## sanity: save resolves the initial email
@u1 = PartialIdxUser.new(uid: 'pw1', email: 'pw1-a@example.com')
@u1.save
PartialIdxUser.find_by_email('pw1-a@example.com')&.uid
#=> "pw1"

## commit_fields on a changed unique-indexed field: new value resolves
@u1.email = 'pw1-b@example.com'
@u1.commit_fields
PartialIdxUser.find_by_email('pw1-b@example.com')&.uid
#=> "pw1"

## commit_fields retracted the old value's mapping (no orphan)
[PartialIdxUser.email_lookup.get('pw1-a@example.com'),
 PartialIdxUser.find_by_email('pw1-a@example.com')]
#=> [nil, nil]

## save_fields on a unique-indexed field: new value resolves
@u1.email = 'pw1-c@example.com'
@u1.save_fields(:email)
PartialIdxUser.find_by_email('pw1-c@example.com')&.uid
#=> "pw1"

## save_fields retracted the old value's mapping (no orphan)
[PartialIdxUser.email_lookup.get('pw1-b@example.com'),
 PartialIdxUser.find_by_email('pw1-b@example.com')]
#=> [nil, nil]

## multi_field_update on a unique-indexed field: new value resolves
@u1.multi_field_update(email: 'pw1-d@example.com')
PartialIdxUser.find_by_email('pw1-d@example.com')&.uid
#=> "pw1"

## multi_field_update retracted the old value's mapping (no orphan)
[PartialIdxUser.email_lookup.get('pw1-c@example.com'),
 PartialIdxUser.find_by_email('pw1-c@example.com')]
#=> [nil, nil]

## a value freed by a partial write can be claimed by another record
@u2 = PartialIdxUser.new(uid: 'pw2', email: 'pw1-c@example.com')
@u2.save
PartialIdxUser.find_by_email('pw1-c@example.com')&.uid
#=> "pw2"

# =============================================
# 2. Fail-closed conflicts: hash untouched
# =============================================

## commit_fields to a value another record owns raises before any write
@u1.email = 'pw1-c@example.com'
@u1.commit_fields
#=!> Familia::RecordExistsError

## the failed commit_fields left the stored hash untouched (raw serialized form)
Familia.dbclient.hget(@u1.dbkey, 'email')
#=> '"pw1-d@example.com"'

## the contested value still maps to its owner
@u1.refresh
PartialIdxUser.email_lookup.get('pw1-c@example.com')
#=> "pw2"

## save_fields to a value another record owns raises before any write
@u1.email = 'pw1-c@example.com'
@u1.save_fields(:email)
#=!> Familia::RecordExistsError

## the failed save_fields left the stored hash untouched (raw serialized form)
@u1.refresh
Familia.dbclient.hget(@u1.dbkey, 'email')
#=> '"pw1-d@example.com"'

## multi_field_update to a value another record owns raises before any write
@u1.multi_field_update(email: 'pw1-c@example.com')
#=!> Familia::RecordExistsError

## the failed multi_field_update left the stored hash untouched (raw serialized form)
Familia.dbclient.hget(@u1.dbkey, 'email')
#=> '"pw1-d@example.com"'

## the failed multi_field_update rolled the in-memory value back clean
[@u1.email, @u1.dirty?(:email)]
#=> ["pw1-d@example.com", false]

## a mixed indexed/non-indexed multi_field_update that loses the claim
## rolls back ALL fields (non-indexed included) and touches no hash field:
## the claim runs before the MULTI, so nothing was queued for either field
begin
  @u1.multi_field_update(email: 'pw1-c@example.com', nickname: 'diverged')
rescue Familia::RecordExistsError
  nil
end
[@u1.email, @u1.nickname, @u1.dirty?(:email), @u1.dirty?(:nickname),
 Familia.dbclient.hget(@u1.dbkey, 'email'), Familia.dbclient.hget(@u1.dbkey, 'nickname')]
#=> ["pw1-d@example.com", nil, false, false, '"pw1-d@example.com"', nil]

# =============================================
# 2b. Failed transactions do not leak index claims
# =============================================
# The unique-index claim is a pre-MULTI CAS that writes the index entry
# itself, so a transaction that never lands must release the entries it
# created -- otherwise the index maps a value to a hash state that was
# never stored. Once EXEC runs, every queued command executed, so an
# errors?-result is ambiguous and the claim is deliberately KEPT.

## an aborted transaction (EXEC never ran) releases the created claim and
## rolls multi_field_update's in-memory state back; the old entry survives
@u3 = PartialIdxUser.new(uid: 'pw3', email: 'pw3-a@example.com')
@u3.save
def @u3.transaction(*) = Familia::MultiResult.new(nil)
@u3.multi_field_update(email: 'pw3-b@example.com')
[@u3.email, PartialIdxUser.email_lookup.get('pw3-b@example.com'),
 PartialIdxUser.email_lookup.get('pw3-a@example.com')]
#=> ["pw3-a@example.com", nil, "pw3"]

## commit_fields releases its created claim on abort too; the in-memory
## value stays set and dirty (documented divergence -- the caller set it)
@u3.email = 'pw3-e@example.com'
@u3.commit_fields
[@u3.email, @u3.dirty?(:email), PartialIdxUser.email_lookup.get('pw3-e@example.com')]
#=> ["pw3-e@example.com", true, nil]

## save_fields releases its created claim on abort, same divergence rule
@u3.refresh
@u3.email = 'pw3-f@example.com'
@u3.save_fields(:email)
[@u3.email, PartialIdxUser.email_lookup.get('pw3-f@example.com')]
#=> ["pw3-f@example.com", nil]

## a transaction that raises (MULTI discarded before EXEC) releases the
## claim before restoring and propagating
@u3.refresh
def @u3.transaction(*) = raise(Familia::Problem, 'forced failure')
begin
  @u3.multi_field_update(email: 'pw3-c@example.com')
rescue Familia::Problem
  nil
end
[@u3.email, PartialIdxUser.email_lookup.get('pw3-c@example.com')]
#=> ["pw3-a@example.com", nil]

## executed-with-errors is ambiguous: EXEC ran every queued command, so the
## hash write may have landed and the claim entry may be the record's valid
## mapping. The claim is KEPT (a leaked claim is recoverable; deleting a
## valid entry is not) while the in-memory state still rolls back.
def @u3.transaction(*) = Familia::MultiResult.new([StandardError.new('boom')])
@u3.multi_field_update(email: 'pw3-g@example.com')
[@u3.email, PartialIdxUser.email_lookup.get('pw3-g@example.com')]
#=> ["pw3-a@example.com", "pw3"]

## the kept claim blocks other records from taking the value in the window
@u5 = PartialIdxUser.new(uid: 'pw5', email: 'pw3-g@example.com')
@u5.save
#=!> Familia::RecordExistsError

## the owner reconciles by saving the value for real: the kept claim
## becomes its valid index entry
@u3.singleton_class.send(:remove_method, :transaction)
@u3.email = 'pw3-g@example.com'
@u3.save
[PartialIdxUser.find_by_email('pw3-g@example.com')&.uid,
 Familia.dbclient.hget(@u3.dbkey, 'email')]
#=> ["pw3", '"pw3-g@example.com"']

# =============================================
# 3. multi_field_fast_write refuses indexed fields
# =============================================

## multi_field_fast_write refuses a unique-indexed field
@u1.multi_field_fast_write(email: 'fast@example.com')
#=!> Familia::IndexedFieldFastWriteError

## the refusal happens before any write: no HMSET, hash untouched
@before = hmset_calls
begin
  @u1.multi_field_fast_write(email: 'fast@example.com', nickname: 'batch')
rescue Familia::IndexedFieldFastWriteError
  nil
end
[hmset_calls - @before,
 Familia.dbclient.hget(@u1.dbkey, 'email'),
 Familia.dbclient.hget(@u1.dbkey, 'nickname')]
#=> [0, '"pw1-d@example.com"', nil]

## the error names the offending field and index
begin
  @u1.multi_field_fast_write(email: 'fast@example.com')
rescue Familia::IndexedFieldFastWriteError => e
  [e.field, e.index_name]
end
#=> [:email, :email_lookup]

## with several indexed fields the ONE error names them all (no discovery
## by retry); field/index_name stay the first pair for older callers
@d1 = PartialIdxDouble.new(did: 'pwd1', email: 'd@example.com', username: 'du')
begin
  @d1.multi_field_fast_write(email: 'x@example.com', username: 'dv', note: 'ok')
rescue Familia::IndexedFieldFastWriteError => e
  [e.field, e.index_name, e.offenders,
   e.message.include?('email'), e.message.include?('username')]
end
#=> [:email, :em_lookup, [[:email, :em_lookup], [:username, :un_lookup]], true, true]

## non-indexed fields still fast-write with a single HMSET
@before = hmset_calls
@u1.multi_field_fast_write(nickname: 'nick')
[@u1.nickname, Familia.dbclient.hget(@u1.dbkey, 'nickname'), hmset_calls - @before]
#=> ["nick", '"nick"', 1]

# =============================================
# 4. Non-indexed fast writer unchanged in all modes
# =============================================

## non-indexed fast writer works outside any transaction
@u1.nickname!('solo')
Familia.dbclient.hget(@u1.dbkey, 'nickname')
#=> '"solo"'

## non-indexed fast writer still queues inside a transaction
@u1.transaction { @u1.nickname!('intxn') }
Familia.dbclient.hget(@u1.dbkey, 'nickname')
#=> '"intxn"'

## non-indexed fast writer still queues inside a pipeline
@u1.pipelined { @u1.nickname!('inpipe') }
Familia.dbclient.hget(@u1.dbkey, 'nickname')
#=> '"inpipe"'

# =============================================
# 5. Multi-index (add-only) via partial writers
# =============================================

## save adds a multi_index record to its bucket
@c1 = PartialIdxBucket.new(custid: 'pwc1', status: 'active')
@c1.save
PartialIdxBucket.status_index_for('active').members
#=> ["pwc1"]

## multi_field_update adds to the new bucket
@c1.multi_field_update(status: 'inactive')
PartialIdxBucket.status_index_for('inactive').members
#=> ["pwc1"]

## add-only semantics: the old bucket entry remains (same as save)
PartialIdxBucket.status_index_for('active').members
#=> ["pwc1"]

## save_fields adds to its bucket under the same add-only semantics
@c1.status = 'pending'
@c1.save_fields(:status)
[PartialIdxBucket.status_index_for('pending').members,
 PartialIdxBucket.status_index_for('inactive').members]
#=> [["pwc1"], ["pwc1"]]

## commit_fields adds to its bucket under the same add-only semantics
@c1.status = 'archived'
@c1.commit_fields
PartialIdxBucket.status_index_for('archived').members
#=> ["pwc1"]

## fast writer on a multi_index field adds to its bucket
@c1.status!('fastlane')
PartialIdxBucket.status_index_for('fastlane').members
#=> ["pwc1"]

## multi_field_fast_write refuses multi_index-backed fields too
@c1.multi_field_fast_write(status: 'refused')
#=!> Familia::IndexedFieldFastWriteError

## fast writer on a multi_index field refuses inside a transaction
@err = nil
@c1.transaction do
  @c1.status!('txn-bucket')
rescue Familia::IndexedFieldFastWriteError => e
  @err = e
end
[@err.class, PartialIdxBucket.status_index_for('txn-bucket').members]
#=> [Familia::IndexedFieldFastWriteError, []]

# =============================================
# 6. Partial writers refuse inside MULTI/pipeline
# =============================================

## commit_fields on a unique-indexed class refuses inside a transaction
## (the guard reads would return futures; save makes the same refusal)
@u1.refresh
@err = nil
@u1.transaction do
  @u1.commit_fields
rescue Familia::OperationModeError => e
  @err = e
end
@err.class
#=> Familia::OperationModeError

## the refused commit_fields queued nothing: hash untouched
Familia.dbclient.hget(@u1.dbkey, 'email')
#=> '"pw1-d@example.com"'

## save_fields on a unique-indexed field refuses inside a transaction,
## before any write and before any index claim
@u1.email = 'txn@example.com'
@err = nil
@u1.transaction do
  @u1.save_fields(:email)
rescue Familia::OperationModeError => e
  @err = e
end
[@err.class, Familia.dbclient.hget(@u1.dbkey, 'email'),
 PartialIdxUser.email_lookup.get('txn@example.com')]
#=> [Familia::OperationModeError, '"pw1-d@example.com"', nil]

## multi_field_update refuses inside a transaction and rolls the
## in-memory state back clean (never-diverged semantics)
@u1.refresh
@err = nil
@u1.transaction do
  @u1.multi_field_update(email: 'txn2@example.com')
rescue Familia::OperationModeError => e
  @err = e
end
[@err.class, @u1.email, @u1.dirty?(:email),
 PartialIdxUser.email_lookup.get('txn2@example.com')]
#=> [Familia::OperationModeError, "pw1-d@example.com", false, nil]

## partial writers refuse inside a pipeline too
@err = nil
@u1.pipelined do
  @u1.commit_fields
rescue Familia::OperationModeError => e
  @err = e
end
@err.class
#=> Familia::OperationModeError

## scoping: a partial write of only non-indexed fields does not trip the
## refusal -- no index work would happen, so the pre-existing reentrant
## behavior (broken in its own way, out of scope here) is unchanged
@err = nil
begin
  @u1.transaction { @u1.save_fields(:nickname) }
rescue StandardError => e
  @err = e
end
@err.is_a?(Familia::OperationModeError)
#=> false

# =============================================
# 7. RecordExistsError#message never raises
# =============================================

## message includes a normal existing_id
Familia::RecordExistsError.new('some:key', existing_id: 'pw2').message
#=> "Key already exists: some:key (existing_id=pw2)"

## message omits an existing_id it cannot interrogate (e.g. a
## Redis::Future-like value lacking nil?/to_s) instead of raising
@weird = BasicObject.new
Familia::RecordExistsError.new('some:key', existing_id: @weird).message
#=> "Key already exists: some:key"

# =============================================
# 8. multi_field_update refuses objid/extid fields
# =============================================
# The objid setter HDELs the old value from the class-level objid_lookup
# hash. That side effect survives the snapshot rollback, so a failed
# update would strip the persisted identifier's lookup entry -- and even a
# successful partial write never re-adds the mapping (only save and
# save_if_not_exists do). Fail-closed, like transient fields.

## setup: a saved owner resolves through its objid_lookup mapping
@o1 = PartialIdxOwner.new(pid: 'po1', label: 'one')
@o1.save
@orig_objid = @o1.objid
PartialIdxOwner.objid_lookup[@orig_objid]
#=> "po1"

## objid is refused up front by multi_field_update
@o1.multi_field_update(objid: 'replacement-objid', label: 'two')
#=!> ArgumentError

## the refusal ran before any setter: objid unchanged, mapping intact, and
## the non-identifier field in the same batch was not applied either
[@o1.objid == @orig_objid, PartialIdxOwner.objid_lookup[@orig_objid], @o1.label]
#=> [true, "po1", "one"]

@u1.destroy! rescue nil
@u2.destroy! rescue nil
@u3.destroy! rescue nil
@c1.destroy! rescue nil
@o1.destroy! rescue nil
cleanup_keys = Familia.dbclient.keys('partial_idx_user:*') +
               Familia.dbclient.keys('partial_idx_bucket:*') +
               Familia.dbclient.keys('partial_idx_double:*') +
               Familia.dbclient.keys('partial_idx_owner:*')
Familia.dbclient.del(*cleanup_keys) if cleanup_keys.any?
