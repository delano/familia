# try/features/relationships/unique_index_cas_try.rb
#
# frozen_string_literal: true

# Server-side CAS enforcement for unique indexes (issue #353).
#
# The read guard (guard_unique_*!) runs before the save MULTI and cannot settle
# a race: two savers both read "unclaimed" and the second HSET silently wins.
# These tests cover the Lua claim that closes it, and the ownership-checked
# release that closes the same hole on the way out.
#
# lib/familia/data_type/types/hashkey.rb          -- claim_field / release_field
# lib/familia/features/relationships/indexing/unique_index_generators.rb
# lib/familia/horreum/persistence.rb              -- claim_unique_indexes!
# docs/adr/0002-watch-for-private-keys-lua-for-shared-keys.md

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

class CasUser < Familia::Horreum
  feature :relationships

  identifier_field :uid
  field :uid
  field :email

  unique_index :email, :email_cas_index
end

# Two unique indexes on one class: exercises the partial-claim rollback path.
class CasDualUser < Familia::Horreum
  feature :relationships

  identifier_field :uid
  field :uid
  field :email
  field :handle

  unique_index :email, :dual_email_index
  unique_index :handle, :dual_handle_index
end

@index = CasUser.email_cas_index

## Setup: start from an empty index
CasUser.email_cas_index.clear
CasUser.email_cas_index.field_count
#=> 0

# ========================================
# HashKey#claim_field -- the CAS primitive
# ========================================

## Claiming an unclaimed field reports :created
@index.claim_field('cas1@test.com', 'u1')
#=> :created

## The claim is durable
@index['cas1@test.com']
#=> 'u1'

## Re-claiming your own field reports :owned (idempotent)
@index.claim_field('cas1@test.com', 'u1')
#=> :owned

## A competing claim returns the current owner rather than overwriting
@index.claim_field('cas1@test.com', 'u2')
#=> 'u1'

## The loser's write did not land
@index['cas1@test.com']
#=> 'u1'

## A legacy JSON-encoded entry still reads as owned by the same identifier
# Pre-2.10.0 unique_index writes stored '"u3"' instead of 'u3'. The read path
# tolerates it, so the CAS must too -- otherwise a record raises against itself.
CasUser.dbclient.hset(@index.dbkey, 'legacy@test.com', '"u3"')
@index.claim_field('legacy@test.com', 'u3')
#=> :owned

## Claiming normalizes the legacy form to the canonical one in place
CasUser.dbclient.hget(@index.dbkey, 'legacy@test.com')
#=> 'u3'

## A legacy entry still blocks a different identifier
CasUser.dbclient.hset(@index.dbkey, 'legacy2@test.com', '"u4"')
@index.claim_field('legacy2@test.com', 'u5')
#=> 'u4'

## claim_field refuses to run inside a transaction
# EVAL queued in a MULTI returns a Future, so its verdict cannot be acted on.
begin
  CasUser.transaction { @index.claim_field('intxn@test.com', 'u9') }
  'no error'
rescue Familia::OperationModeError
  'refused'
end
#=> 'refused'

# ========================================
# HashKey#release_field -- ownership-checked delete
# ========================================

## Releasing a field you own deletes it
@index.claim_field('rel1@test.com', 'r1')
@index.release_field('rel1@test.com', 'r1')
#=> 1

## The entry is gone
@index['rel1@test.com']
#=> nil

## Releasing a field owned by someone else is a no-op
@index.claim_field('rel2@test.com', 'r2')
@index.release_field('rel2@test.com', 'r-other')
#=> 0

## The rightful owner's entry survives
@index['rel2@test.com']
#=> 'r2'

## Releasing an absent field is a no-op
@index.release_field('never-claimed@test.com', 'r2')
#=> 0

# ========================================
# Save path: claim happens before the MULTI
# ========================================

## A save claims the indexed value
CasUser.email_cas_index.clear
@saved = CasUser.new(uid: 'save1', email: 'save1@test.com')
@saved.save
CasUser.email_cas_index['save1@test.com']
#=> 'save1'

## Saving the same record again re-affirms its own claim
@saved.save
CasUser.email_cas_index['save1@test.com']
#=> 'save1'

## A second record saving the same email is rejected
@dup = CasUser.new(uid: 'save2', email: 'save1@test.com')
begin
  @dup.save
  'no error'
rescue Familia::RecordExistsError => e
  e.existing_id
end
#=> 'save1'

## The rejected save left the index pointing at the original owner
CasUser.email_cas_index['save1@test.com']
#=> 'save1'

## Changing an indexed field frees the old value and claims the new one
@saved.email = 'save1-new@test.com'
@saved.save
[CasUser.email_cas_index['save1@test.com'], CasUser.email_cas_index['save1-new@test.com']]
#=> [nil, 'save1']

## The freed value is immediately reusable by another record
@reuser = CasUser.new(uid: 'save3', email: 'save1@test.com')
@reuser.save
CasUser.email_cas_index['save1@test.com']
#=> 'save3'

# ========================================
# Every save path claims before its MULTI
# ========================================
# The in-MULTI HSET asserts a prior claim, so any path that reaches
# persist_to_storage without prepare_for_save would raise. These pin that down.

## atomic_write claims via prepare_for_save
CasUser.email_cas_index.clear
@aw = CasUser.new(uid: 'aw1', email: 'aw1@test.com')
@aw.atomic_write { @aw.uid = 'aw1' }
CasUser.email_cas_index['aw1@test.com']
#=> 'aw1'

## Familia.atomic_write claims for every instance it persists
@aw2 = CasUser.new(uid: 'aw2', email: 'aw2@test.com')
@aw3 = CasUser.new(uid: 'aw3', email: 'aw3@test.com')
Familia.atomic_write(@aw2, @aw3)
[CasUser.email_cas_index['aw2@test.com'], CasUser.email_cas_index['aw3@test.com']]
#=> ['aw2', 'aw3']

## save_if_not_exists! claims too
@aw4 = CasUser.new(uid: 'aw4', email: 'aw4@test.com')
@aw4.save_if_not_exists!
CasUser.email_cas_index['aw4@test.com']
#=> 'aw4'

## A conflict surfaces through atomic_write as RecordExistsError
@aw5 = CasUser.new(uid: 'aw5', email: 'aw1@test.com')
begin
  @aw5.atomic_write { @aw5.uid = 'aw5' }
  'no error'
rescue Familia::RecordExistsError => e
  e.existing_id
end
#=> 'aw1'

# ========================================
# Simulated race: guard passes for both, CAS settles it
# ========================================

## Both records pass the read guard against an empty slot
CasUser.email_cas_index.clear
@race_a = CasUser.new(uid: 'race_a', email: 'race@test.com')
@race_b = CasUser.new(uid: 'race_b', email: 'race@test.com')
begin
  @race_a.guard_unique_email_cas_index!
  @race_b.guard_unique_email_cas_index!
  'both passed'
rescue Familia::RecordExistsError
  'guard caught it'
end
#=> 'both passed'

## Only one of them can claim it
@race_a.claim_unique_email_cas_index!
begin
  @race_b.claim_unique_email_cas_index!
  'no error'
rescue Familia::RecordExistsError => e
  e.existing_id
end
#=> 'race_a'

# ========================================
# In-MULTI writes require a prior claim
# ========================================

## add_to_class_* inside a caller's own transaction refuses without a claim
# The in-transaction HSET can only re-affirm a claim taken before the MULTI
# opened; without one it is the old blind write.
CasUser.email_cas_index.clear
@unclaimed = CasUser.new(uid: 'txn1', email: 'txn1@test.com')
begin
  CasUser.transaction { @unclaimed.add_to_class_email_cas_index }
  'no error'
rescue Familia::OperationModeError
  'refused'
end
#=> 'refused'

## Nothing was written by the refused call
CasUser.email_cas_index['txn1@test.com']
#=> nil

## update_in_class_* refuses the same way -- it is the path save actually takes
begin
  CasUser.transaction { @unclaimed.update_in_class_email_cas_index }
  'no error'
rescue Familia::OperationModeError
  'refused'
end
#=> 'refused'

## Claiming first makes the in-transaction re-affirmation legal
@unclaimed.send(:prepare_for_save)
CasUser.transaction { @unclaimed.add_to_class_email_cas_index }
CasUser.email_cas_index['txn1@test.com']
#=> 'txn1'

# ========================================
# Partial-claim rollback across two unique indexes
# ========================================

## Seed a handle owned by an existing record
CasDualUser.dual_email_index.clear
CasDualUser.dual_handle_index.clear
@incumbent = CasDualUser.new(uid: 'inc', email: 'inc@test.com', handle: 'taken')
@incumbent.save
CasDualUser.dual_handle_index['taken']
#=> 'inc'

## A save whose email is free but whose handle collides is rejected
@partial = CasDualUser.new(uid: 'part', email: 'free@test.com', handle: 'taken')
begin
  @partial.save
  'no error'
rescue Familia::RecordExistsError => e
  e.existing_id
end
#=> 'inc'

## Nothing was claimed for the rejected record
# In this shape guard_unique_indexes! catches it before any claim is written --
# that is the whole point of running the read pass across every index first.
CasDualUser.dual_email_index['free@test.com']
#=> nil

## Driving claim_unique_indexes! directly reaches the rollback branch
# The guard short-circuits the case above, so exercise the compensation path on
# its own: email is free (claimed :created), handle collides (raises). The
# email claim must be released on the way out or 'free@test.com' is stranded
# forever on a record that never saved.
@rollback = CasDualUser.new(uid: 'rb', email: 'free@test.com', handle: 'taken')
begin
  @rollback.send(:claim_unique_indexes!)
  'no error'
rescue Familia::RecordExistsError => e
  e.existing_id
end
#=> 'inc'

## The :created claim taken earlier in that run was rolled back
CasDualUser.dual_email_index['free@test.com']
#=> nil

## So the freed email is still claimable by another record
@other = CasDualUser.new(uid: 'oth', email: 'free@test.com', handle: 'untaken')
@other.save
CasDualUser.dual_email_index['free@test.com']
#=> 'oth'

## An entry the record already owned is NOT rolled back by a later conflict
# @other owns free@test.com from the save above, so its email claim comes back
# :owned rather than :created. Rolling that back would destroy valid state --
# the entry predates this call. Again driven directly, since the guard would
# otherwise short-circuit before any claim runs.
@other.handle = 'taken'
begin
  @other.send(:claim_unique_indexes!)
rescue Familia::RecordExistsError
  nil
end
CasDualUser.dual_email_index['free@test.com']
#=> 'oth'

# ========================================
# destroy! releases only entries the record owns
# ========================================

## A stale in-memory value cannot evict the current owner's claim
# @stale still believes it holds contested@test.com; @owner has since claimed
# it. A blind HDEL on destroy would delete @owner's live entry.
CasUser.email_cas_index.clear
@stale = CasUser.new(uid: 'stale', email: 'contested@test.com')
@stale.save
@stale.remove_from_class_email_cas_index
@owner = CasUser.new(uid: 'own', email: 'contested@test.com')
@owner.save
@stale.destroy!
CasUser.email_cas_index['contested@test.com']
#=> 'own'

## Destroying the actual owner does release the entry
@owner.destroy!
CasUser.email_cas_index['contested@test.com']
#=> nil

# ========================================
# Teardown
# ========================================

@teardown_ids = %w[save1 save2 save3 race_a race_b txn1 own stale aw1 aw2 aw3 aw4 aw5]
@teardown_ids.each { |uid| CasUser.new(uid: uid).destroy! rescue nil }
%w[inc part oth].each { |uid| CasDualUser.new(uid: uid).destroy! rescue nil }
CasUser.email_cas_index.clear
CasDualUser.dual_email_index.clear
CasDualUser.dual_handle_index.clear
CasUser.instances.clear
CasDualUser.instances.clear
