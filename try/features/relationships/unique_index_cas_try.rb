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

## Calling claim_unique_<index>! directly is enough on its own
# This is the escape hatch the OperationModeError message points at, so it has
# to actually satisfy the check -- the per-index claim records its own ledger
# entry rather than relying on prepare_for_save to do it.
@direct = CasUser.new(uid: 'txn2', email: 'txn2@test.com')
@direct.claim_unique_email_cas_index!
CasUser.transaction { @direct.add_to_class_email_cas_index }
CasUser.email_cas_index['txn2@test.com']
#=> 'txn2'

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
# The claim ledger records the value, not just the index name
# ========================================
# The in-MULTI HSET is only sound as a re-affirmation of *the value that was
# claimed*. An index-name-only ledger would vouch for a value no CAS ever saw
# in two reachable shapes, both of them the blind write this issue removes.

## prepare_for_save records the claimed value
CasUser.email_cas_index.clear
@ledger_ok = CasUser.new(uid: 'led_ok', email: 'ok@test.com')
@ledger_ok.send(:prepare_for_save)
@ledger_ok.send(:unique_index_claimed?, :email_cas_index, 'ok@test.com')
#=> true

## and vouches for that value only
@ledger_ok.send(:unique_index_claimed?, :email_cas_index, 'other@test.com')
#=> false

## A nil indexed field claims nothing, so the ledger stays empty
# Recording the index name here would let a later write of any value ride on an
# entry that was never taken.
@ledger_nil = CasUser.new(uid: 'led_nil')
@ledger_nil.send(:prepare_for_save)
@ledger_nil.instance_variable_get(:@unique_index_claims)
#=> {}

## An atomic_write block that changes the indexed field is refused
# prepare_for_save claims the value the record holds when the block opens; the
# block then runs INSIDE the MULTI. Reassigning the field there reaches the
# HSET with a value no CAS settled.
CasUser.email_cas_index.clear
@led_inc = CasUser.new(uid: 'led_inc', email: 'ledger@test.com')
@led_inc.save
@led_mut = CasUser.new(uid: 'led_mut', email: 'ledgerown@test.com')
begin
  @led_mut.atomic_write { @led_mut.email = 'ledger@test.com' }
  'no error'
rescue Familia::OperationModeError
  'refused'
end
#=> 'refused'

## and the incumbent's entry survives it
CasUser.email_cas_index['ledger@test.com']
#=> 'led_inc'

## The ledger does not outlive the save that populated it
# A caller-opened transaction after the indexed field changed must not find the
# index still marked claimed from the previous save.
@led_stale = CasUser.new(uid: 'led_stale', email: 'stale1@test.com')
@led_stale.save
@led_stale.email = 'stale2@test.com'
begin
  CasUser.transaction { @led_stale.add_to_class_email_cas_index }
  'no error'
rescue Familia::OperationModeError
  'refused'
end
#=> 'refused'

## so the unclaimed value was never written
CasUser.email_cas_index['stale2@test.com']
#=> nil

# ========================================
# Teardown
# ========================================

@teardown_ids = %w[save1 save2 save3 race_a race_b txn1 txn2 own stale aw1 aw2 aw3 aw4 aw5
                   led_ok led_nil led_inc led_mut led_stale]
@teardown_ids.each { |uid| CasUser.new(uid: uid).destroy! rescue nil }
%w[inc part oth].each { |uid| CasDualUser.new(uid: uid).destroy! rescue nil }
CasUser.email_cas_index.clear
CasDualUser.dual_email_index.clear
CasDualUser.dual_handle_index.clear
CasUser.instances.clear
CasDualUser.instances.clear
