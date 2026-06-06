# try/features/cross_model_atomic_write_try.rb
#
# Tests for the module-level Familia.atomic_write(*instances, ...) which
# persists multiple (possibly cross-class) Horreum instances in ONE
# MULTI/EXEC. See lib/familia/connection/operations.rb#atomic_write.
#
# The read/write split is the key constraint: prepare_for_save (timestamps +
# unique-index reads) runs OUTSIDE the txn; persist_to_storage (HMSET/EXPIRE/
# index HSET/instances ZADD) runs INSIDE. Anchoring the MULTI on
# instances.first.dbclient is only correct because the guard enforces all
# roots share ONE logical database, so every instance routes to that same
# connection inside the MULTI.

require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Two models that mirror the issue's POCustomer/POOrg. Both live on the
# default logical database (0) so they share one connection inside the MULTI.
class CMCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
  field :org_id
  set :orgs
end

class CMOrg < Familia::Horreum
  identifier_field :orgid
  field :orgid
  field :name
  field :owner_id
  set :members
end

# Two models that span DIFFERENT logical databases, for the CrossDatabaseError
# guard. CMDbZero resolves to 0, CMDbFive to 5 -- MULTI/EXEC cannot cross them.
class CMDbZero < Familia::Horreum
  logical_database 0
  identifier_field :id
  field :id
  field :name
end

class CMDbFive < Familia::Horreum
  logical_database 5
  identifier_field :id
  field :id
  field :name
end

# Raw DEL sweep for teardown. destroy! raises NoIdentifier on partial keys
# (the create-only race intentionally creates a key with no identifier field),
# so flush keys directly via a second raw connection.
def flush_cross_model_keys!
  raw = Redis.new(url: Familia.uri.to_s)
  %w[cm_customer:* cm_org:* cm_db_zero:* cm_strict_customer:* cm_strict_org:*].each do |pattern|
    keys = raw.keys(pattern)
    raw.del(*keys) unless keys.empty?
  end
ensure
  raw&.close
end

# CMDbFive lives on database 5; sweep it on its own connection.
def flush_cross_model_db5!
  raw = Redis.new(url: "#{Familia.uri}/5")
  keys = raw.keys('cm_db_five:*')
  raw.del(*keys) unless keys.empty?
ensure
  raw&.close
end

CMCustomer.instances.clear
CMOrg.instances.clear
flush_cross_model_keys!
flush_cross_model_db5!

## 1a. Two models persisted atomically: a separate Redis probe sees NEITHER
## key mid-transaction. The probe runs INSIDE the user block (which executes
## inside the open MULTI), so its reads observe pre-commit state.
@probe1 = Redis.new(url: Familia.uri.to_s)
@cust1 = CMCustomer.new(custid: 'cm_cust_1', name: 'Pending')
@org1 = CMOrg.new(orgid: 'cm_org_1', name: 'PendingOrg')
@mid_txn_seen = nil
Familia.atomic_write(@cust1, @org1) do
  @cust1.name = 'Acme Owner'
  @org1.name = 'Acme Inc'
  @org1.owner_id = @cust1.identifier
  @cust1.orgs.add(@org1.identifier)
  @org1.members.add(@cust1.identifier)
  # Mid-transaction probe on a SECOND connection: neither key is visible yet
  # because the MULTI has not EXEC'd.
  @mid_txn_seen = [@probe1.exists(@cust1.dbkey), @probe1.exists(@org1.dbkey)]
end
@mid_txn_seen
#=> [0, 0]

## 1b. After the MULTI commits, BOTH keys exist (probed on the second connection)
[@probe1.exists(@cust1.dbkey), @probe1.exists(@org1.dbkey)]
#=> [1, 1]

## 1c. Scalars committed on both models
@r_cust1 = CMCustomer.find_by_id('cm_cust_1')
@r_org1 = CMOrg.find_by_id('cm_org_1')
[@r_cust1.name, @r_org1.name, @r_org1.owner_id]
#=> ['Acme Owner', 'Acme Inc', 'cm_cust_1']

## 1d. Collection mutations committed on both models
[@r_cust1.orgs.members.sort, @r_org1.members.members.sort]
#=> [['cm_org_1'], ['cm_cust_1']]

## 1e. Both roots registered in their instances timelines
[CMCustomer.in_instances?('cm_cust_1'), CMOrg.in_instances?('cm_org_1')]
#=> [true, true]

## 2. An exception raised inside the user block rolls back BOTH: neither key
## exists afterward, and dirty state is preserved on both instances.
@cust2 = CMCustomer.new(custid: 'cm_cust_2', name: 'RollbackCust')
@org2 = CMOrg.new(orgid: 'cm_org_2', name: 'RollbackOrg')
@raised2 = false
begin
  Familia.atomic_write(@cust2, @org2) do
    @cust2.name = 'ShouldNotPersist'
    @org2.name = 'ShouldNotPersist'
    @cust2.orgs.add('ghost')
    raise 'boom'
  end
rescue RuntimeError
  @raised2 = true
end
@probe2 = Redis.new(url: Familia.uri.to_s)
[
  @raised2,
  @probe2.exists(@cust2.dbkey),
  @probe2.exists(@org2.dbkey),
  @cust2.dirty?,
  @org2.dirty?,
]
#=> [true, 0, 0, true, true]

## 3a. CrossDatabaseError raised when roots span databases (0 vs 5), BEFORE
## any write. The synthetic "(root)" field_name identifies the offending root.
@a3 = CMDbZero.new(id: 'cm_a3', name: 'Zero')
@b3 = CMDbFive.new(id: 'cm_b3', name: 'Five')
begin
  Familia.atomic_write(@a3, @b3) do
    @a3.name = 'WroteZero'
    @b3.name = 'WroteFive'
  end
  :no_raise
rescue Familia::CrossDatabaseError => e
  [:raised, e.field_database, e.horreum_database, e.field_name.include?('(root)')]
end
#=> [:raised, 5, 0, true]

## 3b. No writes landed for either root on the cross-db attempt
@probe3a = Redis.new(url: Familia.uri.to_s)
@probe3b = Redis.new(url: "#{Familia.uri}/5")
[@probe3a.exists(@a3.dbkey), @probe3b.exists(@b3.dbkey)]
#=> [0, 0]

## 4a. Dirty state cleared for ALL roots on success
@cust4 = CMCustomer.new(custid: 'cm_cust_4', name: 'DirtyClear')
@org4 = CMOrg.new(orgid: 'cm_org_4', name: 'DirtyClearOrg')
@ret4 = Familia.atomic_write(@cust4, @org4) do
  @cust4.name = 'CustChanged'
  @org4.name = 'OrgChanged'
end
[@ret4, @cust4.dirty?, @org4.dirty?]
#=> [true, false, false]

## 4b. Dirty state left intact for ALL roots when the MultiResult is
## unsuccessful (a queued command returns an Exception object -- MULTI/EXEC
## does NOT raise for per-command errors). Stub execute_normal_transaction to
## return a failed MultiResult after running the block, so scalars are touched
## but neither instance is cleared.
##
## NOTE: the stub does not set Fiber[:familia_transaction], so persist_to_storage
## resolves a live connection and actually writes the dirty values to Redis (the
## teardown flush clears them before any read-back). This is an intentional
## simplification to exercise the dirty-state-preservation path -- it is NOT a
## faithful failed-MULTI (a real aborted EXEC writes nothing); Familia.atomic_write
## does not itself roll back partial Redis writes.
@cust4b = CMCustomer.new(custid: 'cm_cust_4b', name: 'DirtyBefore')
@org4b = CMOrg.new(orgid: 'cm_org_4b', name: 'DirtyBeforeOrg')
@cust4b.save
@org4b.save
@cust4b.name = 'CustDirtyAfter'
@org4b.name = 'OrgDirtyAfter'
@failed_mr = Familia::MultiResult.new(['OK', RuntimeError.new('simulated command failure')])
@orig_ent = Familia::Connection::TransactionCore.method(:execute_normal_transaction)
Familia::Connection::TransactionCore.define_singleton_method(:execute_normal_transaction) do |_proc, &blk|
  blk.call(nil)  # run persist_all so scalars/collections are touched
  @failed_mr
end
begin
  @ret4b = Familia.atomic_write(@cust4b, @org4b) do
    @cust4b.name = 'CustDirtyAfter'
    @org4b.name = 'OrgDirtyAfter'
  end
ensure
  Familia::Connection::TransactionCore.define_singleton_method(:execute_normal_transaction, @orig_ent)
end
[@ret4b, @cust4b.dirty?, @org4b.dirty?]
#=> [false, true, true]

## 5. Nesting guard: calling Familia.atomic_write inside an open
## Familia.transaction { } raises OperationModeError (it opens its own
## MULTI/EXEC and cannot be nested).
@cust5 = CMCustomer.new(custid: 'cm_cust_5', name: 'Nested')
@org5 = CMOrg.new(orgid: 'cm_org_5', name: 'NestedOrg')
begin
  Familia.transaction do
    Familia.atomic_write(@cust5, @org5) { @cust5.name = 'fail' }
  end
  :no_raise
rescue Familia::OperationModeError
  :raised
end
#=> :raised

## 5b. atomic_write with no instances raises ArgumentError
begin
  Familia.atomic_write { nil }
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

## 5c. pre_check without watch_keys raises ArgumentError
@cust5c = CMCustomer.new(custid: 'cm_cust_5c', name: 'NoWatch')
begin
  Familia.atomic_write(@cust5c, pre_check: -> { true }) { @cust5c.name = 'x' }
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

## 6a. Create-only happy path: neither key pre-exists, so both are created.
@cust6 = CMCustomer.new(custid: 'cm_cust_6', name: 'CreateOnly')
@org6 = CMOrg.new(orgid: 'cm_org_6', name: 'CreateOnlyOrg')
@ret6 = Familia.atomic_write(@cust6, @org6,
  watch_keys: [@cust6.dbkey, @org6.dbkey],
  pre_check: -> { [@cust6, @org6].each { |r| raise Familia::RecordExistsError, r.dbkey if r.exists? } }
) do
  @cust6.name = 'CreatedCust'
  @org6.owner_id = @cust6.identifier
end
@r_cust6 = CMCustomer.find_by_id('cm_cust_6')
@r_org6 = CMOrg.find_by_id('cm_org_6')
[@ret6, @r_cust6.name, @r_org6.owner_id]
#=> [true, 'CreatedCust', 'cm_cust_6']

## 6b. Create-only REAL concurrent creation. The org instance's exists? is
## stubbed so that on attempt 1 it reports false (existence check passes) AND,
## as a side effect, a racer creates the org key from a SECOND connection --
## inside the WATCH window. So attempt 1 reaches EXEC, which Redis aborts
## because the watched org key changed; the primitive retries. On attempt 2
## the stub reflects reality (key exists) so the existence check raises
## RecordExistsError -- no silent overwrite of the racer's row. A mutable box
## counts attempts (singleton method blocks evaluate @ivars against the
## singleton object, so use a lexical local) and drives determinism without
## sleeps.
@racer6 = Redis.new(url: Familia.uri.to_s)
@cust6b = CMCustomer.new(custid: 'cm_cust_6b', name: 'Victim')
@org6b = CMOrg.new(orgid: 'cm_org_6b', name: 'VictimOrg')
# Lexical locals: a singleton method block evaluates @ivars against the
# singleton object (the instance), not this top-level binding, so capture the
# racer connection and attempt counter as locals.
race_box = [0]
race_conn = @racer6
@race_box = race_box
real_org_exists = CMOrg.instance_method(:exists?)
@org6b.define_singleton_method(:exists?) do
  race_box[0] += 1
  if race_box[0] == 1
    # Report absent, but as a side effect create the key out-of-band from a
    # second connection -- inside the WATCH window -- so attempt 1's EXEC is
    # aborted by the changed watched key, forcing a genuine retry.
    race_conn.hset(dbkey, 'name', 'RacerOwnedOrg')
    false
  else
    real_org_exists.bind(self).call # now reflects reality: the key exists
  end
end
@raised6 = nil
begin
  Familia.atomic_write(@cust6b, @org6b,
    watch_keys: [@cust6b.dbkey, @org6b.dbkey],
    pre_check: -> {
      [@cust6b, @org6b].each { |r| raise Familia::RecordExistsError, r.dbkey if r.exists? }
    }
  ) do
    @cust6b.name = 'ShouldNotOverwrite'
    @org6b.name = 'ShouldNotOverwrite'
  end
  @raised6 = :no_raise
rescue Familia::RecordExistsError
  @raised6 = :record_exists
rescue Familia::OptimisticLockError
  @raised6 = :optimistic_lock
end
# Either outcome is acceptable per spec (RecordExistsError once the racer's key
# is seen, or OptimisticLockError if retries are exhausted); both prove it did
# NOT silently overwrite. It must have taken at least 2 attempts (the WATCH
# abort on attempt 1 forced a retry).
[
  [:record_exists, :optimistic_lock].include?(@raised6),
  @race_box[0] >= 2,
]
#=> [true, true]

## 6c. ... and the racer's value survived (atomic_write did not overwrite it),
## and the victim's own key was never written under its identifier.
[
  @racer6.hget(@org6b.dbkey, 'name'),
  @racer6.exists(@cust6b.dbkey),
]
#=> ['RacerOwnedOrg', 0]

## 7. Dirty-write suppression: Familia.atomic_write activates atomic_write_mode?
## on every instance (like the instance-level variant), so collection mutations
## in the user block against just-dirtied scalars do not fire dirty-write
## warnings -- or, under dirty_write_warnings :strict, a Familia::Problem raise.
## Without that activation this happy path would raise. (Regression test for the
## #300 review finding.)
class CMStrictCustomer < Familia::Horreum
  dirty_write_warnings :strict
  identifier_field :custid
  field :custid
  field :name
  set :orgs
end
class CMStrictOrg < Familia::Horreum
  dirty_write_warnings :strict
  identifier_field :orgid
  field :orgid
  field :name
  set :members
end
CMStrictCustomer.instances.clear
CMStrictOrg.instances.clear
@scust7 = CMStrictCustomer.new(custid: 'cm_strict_cust_7', name: 'S')
@sorg7 = CMStrictOrg.new(orgid: 'cm_strict_org_7', name: 'SO')
@strict7 = begin
  Familia.atomic_write(@scust7, @sorg7) do
    @scust7.name = 'StrictChanged'        # dirties a scalar
    @scust7.orgs.add(@sorg7.identifier)   # collection mutation on a dirtied :strict parent
    @sorg7.members.add(@scust7.identifier)
  end
rescue Familia::Problem => e
  [:raised, e.message.to_s[0, 40]]
end
@r_scust7 = CMStrictCustomer.find_by_id('cm_strict_cust_7')
[@strict7, @r_scust7.orgs.members]
#=> [true, ['cm_strict_org_7']]

## 8. Non-watched path honors execute_transaction's handler-compatibility gate
## (regression for the #300 review). When the resolved connection's handler
## disallows transactions (fiber-pinned FiberConnectionHandler, allows_transaction
## == false) and transaction_mode is :strict, Familia.atomic_write must surface a
## descriptive OperationModeError via the gate -- not issue a raw MULTI on an
## unsupported connection. Routing the non-watched branch through instance
## #transaction (instead of execute_normal_transaction directly) inherits it.
## Globals are restored in the ensure to avoid cross-test pollution.
@prev_txn_mode8 = Familia.transaction_mode
@conn8 = CMCustomer.create_dbclient
@cust8 = CMCustomer.new(custid: 'cm_cust_8', name: 'GateCheck')
@gate8 = begin
  Familia.configure { |c| c.transaction_mode = :strict }
  Fiber[:familia_connection] = [@conn8, Familia.middleware_version]
  Fiber[:familia_connection_handler_class] = Familia::Connection::FiberConnectionHandler
  begin
    Familia.atomic_write(@cust8) { @cust8.name = 'ShouldNotRawMulti' }
    :no_raise
  rescue Familia::OperationModeError
    :raised
  end
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
  Familia.configure { |c| c.transaction_mode = @prev_txn_mode8 }
  @conn8&.close
end
@gate8
#=> :raised

# Cleanup
@probe1&.close
@probe2&.close
@probe3a&.close
@probe3b&.close
@racer6&.close
CMCustomer.instances.clear
CMOrg.instances.clear
CMStrictCustomer.instances.clear
CMStrictOrg.instances.clear
flush_cross_model_keys!
flush_cross_model_db5!
