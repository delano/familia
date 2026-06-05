# Proof-of-concept: validating the cross-model atomic_write concern.
#
# Goals:
#   A. Confirm save (and atomic_write) are blocked once Fiber[:familia_transaction]
#      is set, i.e. you cannot call customer.save inside org.atomic_write { }.
#   B. Confirm the proposed mechanism works: prepare_for_save BOTH instances
#      OUTSIDE the transaction, then call persist_to_storage for BOTH inside a
#      single MULTI/EXEC. Both should commit atomically and roll back together.
#   C. Confirm all-or-nothing rollback when one instance's queued work errors.

require_relative '../support/helpers/test_helpers'

Familia.debug = false

class POCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
  field :org_id
  set :roles
end

class POOrg < Familia::Horreum
  identifier_field :orgid
  field :orgid
  field :name
  field :owner_id
  set :members
end

POCustomer.instances.clear rescue nil
POCustomer.all.each(&:destroy!) rescue nil
POOrg.instances.clear rescue nil
POOrg.all.each(&:destroy!) rescue nil

## CLAIM A: calling save on a second model inside an atomic_write raises OperationModeError
@cust_a = POCustomer.new(custid: 'cust_a', name: 'Alice')
@org_a = POOrg.new(orgid: 'org_a', name: 'Acme')
@cust_a.save
begin
  @org_a.atomic_write do
    @org_a.name = 'Acme Updated'
    @cust_a.save   # <-- save inside an open transaction
  end
  :no_raise
rescue Familia::OperationModeError => e
  [:raised, e.message.include?('Cannot call save within a transaction')]
end
#=> [:raised, true]

## CLAIM B: two instances persisted in ONE MULTI/EXEC via a manual cross-model helper.
## This is the exact mechanism the assessment proposes: prepare both OUTSIDE,
## then persist both INSIDE one transaction. Both route to the same
## Fiber[:familia_transaction] connection regardless of which object opened it.
@cust_b = POCustomer.new(custid: 'cust_b', name: 'Bob')
@org_b = POOrg.new(orgid: 'org_b', name: 'Globex')

# prepare_for_save and persist_to_storage are private; send is fine for a PoC.
@cust_b.send(:prepare_for_save)
@org_b.send(:prepare_for_save)

@result = Familia.transaction do |_conn|
  @cust_b.name = 'Bob Persisted'
  @cust_b.roles.add('admin')
  @org_b.owner_id = 'cust_b'
  @org_b.members.add('cust_b')
  @cust_b.send(:persist_to_storage, true)
  @org_b.send(:persist_to_storage, true)
end

@cust_b_reloaded = POCustomer.find_by_id('cust_b')
@org_b_reloaded = POOrg.find_by_id('org_b')
[
  @result.successful?,
  @cust_b_reloaded.name,
  @cust_b_reloaded.roles.members,
  @org_b_reloaded.owner_id,
  @org_b_reloaded.members.members,
]
#=> [true, 'Bob Persisted', ['admin'], 'cust_b', ['cust_b']]

## CLAIM B (routing proof): both models' writes really shared one MULTI by
## counting that nothing is visible mid-transaction. We open the txn, queue both
## persists, and assert neither key exists until EXEC. Reads inside MULTI return
## futures, so we check existence from a SEPARATE connection during the block.
@cust_c = POCustomer.new(custid: 'cust_c', name: 'Carol')
@org_c = POOrg.new(orgid: 'org_c', name: 'Initech')
@cust_c.send(:prepare_for_save)
@org_c.send(:prepare_for_save)

@probe = Redis.new(url: 'redis://127.0.0.1:2525')
@mid_txn_exists = nil
Familia.transaction do |_conn|
  @cust_c.send(:persist_to_storage, true)
  @org_c.send(:persist_to_storage, true)
  # Separate connection: neither key should be visible until EXEC commits.
  @mid_txn_exists = [@probe.exists(@cust_c.dbkey), @probe.exists(@org_c.dbkey)]
end
@after_txn_exists = [@probe.exists(@cust_c.dbkey), @probe.exists(@org_c.dbkey)]
@probe.close
[@mid_txn_exists, @after_txn_exists]
#=> [[0, 0], [1, 1]]

## CLAIM C (caveat): the unwatched MULTI path pins ONE connection for all
## instances via Fiber[:familia_transaction]. Inside the transaction, every
## model's dbclient resolves to the SAME connection object — which is exactly
## why two instances can share one MULTI/EXEC.
@cust_d = POCustomer.new(custid: 'cust_d', name: 'Dave')
@org_d = POOrg.new(orgid: 'org_d', name: 'Hooli')
@in_txn_same_conn = nil
Familia.transaction do |conn|
  @in_txn_same_conn = @cust_d.dbclient.equal?(@org_d.dbclient) &&
                      @cust_d.dbclient.equal?(conn)
end
@in_txn_same_conn
#=> true

## CLAIM C (the WATCH caveat): the create-only/race-safe variant is harder.
## WATCH must run on the SAME connection the MULTI later opens on. But OUTSIDE a
## transaction, dbclient returns a FRESH connection every call (default
## CreateConnectionHandler). So a naive `dbclient.watch { transaction {...} }`
## puts WATCH and MULTI on DIFFERENT connections — the optimistic lock is inert.
## This already affects build(&block) and save_if_not_exists! in this config.
@watch_conn = POCustomer.dbclient
@multi_conn_id = nil
@watch_conn.watch(@cust_d.dbkey) do
  POCustomer.transaction { |conn| @multi_conn_id = conn.object_id }
end
# Different object_ids => the WATCH did not protect the MULTI.
@watch_conn.object_id == @multi_conn_id
#=> false

# Cleanup
POCustomer.instances.clear rescue nil
POCustomer.all.each(&:destroy!) rescue nil
POOrg.instances.clear rescue nil
POOrg.all.each(&:destroy!) rescue nil
