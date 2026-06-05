# try/investigation/cross_model_atomic_poc_try.rb
#
# Proof-of-concept for module-level Familia.atomic_write(*instances, ...).
#
# Demonstrates two properties on the DEFAULT connection config:
#
#   1. Familia.atomic_write commits two (cross-class) models in ONE MULTI/EXEC:
#      a separate raw connection sees NEITHER key mid-transaction and BOTH
#      after EXEC.
#   2. The create-only path (watch_keys: + a pre_check that rejects existing
#      keys) is now RACE-SAFE: a concurrent creation of a watched key during
#      the WATCH window aborts the whole MULTI and the retry surfaces the
#      conflict instead of silently overwriting.
#
# Pre-fix contrast (for the record): before the committed
# TransactionCore.execute_watched_transaction fix, WATCH and the MULTI/EXEC
# could resolve to DIFFERENT pooled connections, so the WATCH was inert -- a
# concurrent creation slipped through and atomic_write silently overwrote the
# racer's row. Now WATCH + MULTI/EXEC share one resolved connection, so the
# optimistic lock actually fires.

require_relative '../support/helpers/test_helpers'

Familia.debug = false

class PocCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
  set :orgs
end

class PocOrg < Familia::Horreum
  identifier_field :orgid
  field :orgid
  field :name
  field :owner_id
end

# Raw DEL sweep (destroy! raises NoIdentifier on partial keys created by the
# race probe, so flush directly via a second connection).
def flush_poc_keys!
  raw = Redis.new(url: Familia.uri.to_s)
  %w[poc_customer:* poc_org:*].each do |pattern|
    keys = raw.keys(pattern)
    raw.del(*keys) unless keys.empty?
  end
ensure
  raw&.close
end

PocCustomer.instances.clear
PocOrg.instances.clear
flush_poc_keys!

## PoC 1: two models commit in ONE MULTI/EXEC. A separate raw connection
## probes mid-transaction (inside the user block, which runs inside the open
## MULTI) and sees NEITHER key; after EXEC it sees BOTH.
@probe = Redis.new(url: Familia.uri.to_s)
@cust = PocCustomer.new(custid: 'poc_cust', name: 'Pending')
@org = PocOrg.new(orgid: 'poc_org', name: 'PendingOrg')
@during = nil
Familia.atomic_write(@cust, @org) do
  @cust.name = 'Acme Owner'
  @org.name = 'Acme Inc'
  @org.owner_id = @cust.identifier
  @cust.orgs.add(@org.identifier)
  @during = [@probe.exists(@cust.dbkey), @probe.exists(@org.dbkey)]
end
@after = [@probe.exists(@cust.dbkey), @probe.exists(@org.dbkey)]
# during: neither visible (MULTI not yet EXEC'd); after: both visible.
[@during, @after]
#=> [[0, 0], [1, 1]]

## PoC 1b: the committed values are correct on both models
@rc = PocCustomer.find_by_id('poc_cust')
@ro = PocOrg.find_by_id('poc_org')
[@rc.name, @rc.orgs.members, @ro.name, @ro.owner_id]
#=> ['Acme Owner', ['poc_org'], 'Acme Inc', 'poc_cust']

## PoC 2: create-only path is race-safe on the default connection. The org's
## exists? is stubbed so attempt 1 reports false (existence check passes) but,
## as a side effect, a racer creates the org key from a SECOND connection
## inside the WATCH window. Attempt 1's EXEC is aborted (watched key changed);
## the retry's existence check sees the racer's key and raises
## RecordExistsError -- the racer's value is NOT overwritten.
@racer = Redis.new(url: Familia.uri.to_s)
@cust2 = PocCustomer.new(custid: 'poc_cust2', name: 'Victim')
@org2 = PocOrg.new(orgid: 'poc_org2', name: 'VictimOrg')
# Singleton-method blocks evaluate @ivars against the singleton object, so use
# lexical locals for the racer connection and attempt counter.
attempt_box = [0]
racer_conn = @racer
@attempt_box = attempt_box
real_exists = PocOrg.instance_method(:exists?)
@org2.define_singleton_method(:exists?) do
  attempt_box[0] += 1
  if attempt_box[0] == 1
    racer_conn.hset(dbkey, 'name', 'RacerOwned')  # out-of-band, inside WATCH window
    false
  else
    real_exists.bind(self).call
  end
end
@outcome = begin
  Familia.atomic_write(@cust2, @org2,
    watch_keys: [@cust2.dbkey, @org2.dbkey],
    pre_check: -> { [@cust2, @org2].each { |r| raise Familia::RecordExistsError, r.dbkey if r.exists? } }
  ) { @org2.name = 'ShouldNotOverwrite' }
  :no_raise
rescue Familia::RecordExistsError
  :record_exists
rescue Familia::OptimisticLockError
  :optimistic_lock
end
# Took >=2 attempts (attempt 1 aborted by WATCH), raised rather than overwrote.
[[:record_exists, :optimistic_lock].include?(@outcome), @attempt_box[0] >= 2]
#=> [true, true]

## PoC 2b: the racer's value survived (no silent overwrite) and the victim's
## own customer key was never written under its identifier.
[@racer.hget(@org2.dbkey, 'name'), Redis.new(url: Familia.uri.to_s).exists(@cust2.dbkey)]
#=> ['RacerOwned', 0]

# Cleanup
@probe&.close
@racer&.close
PocCustomer.instances.clear
PocOrg.instances.clear
flush_poc_keys!
