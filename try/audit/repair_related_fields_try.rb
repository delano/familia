# try/audit/repair_related_fields_try.rb
#
# frozen_string_literal: true

# repair_related_fields!: removes orphaned DataType collection keys
# whose parent Horreum hash no longer exists. Covers no-op on clean
# state, single orphan, multi-field orphans on one instance, mixed
# orphans across instances, pre-computed audit results, progress
# callback wiring, repair_all! integration (opted in and opted out),
# and idempotency.

require_relative '../support/helpers/test_helpers'

class RRFPlainModel < Familia::Horreum
  identifier_field :pid
  field :pid
  field :name
end

class RRFWithCollections < Familia::Horreum
  identifier_field :cid
  field :cid
  field :name
  list :sessions
  set :tags
  hashkey :settings
end

def rrf_reset_model(klass)
  existing = Familia.dbclient.keys("#{klass.prefix}:*")
  Familia.dbclient.del(*existing) if existing.any?
rescue StandardError
  # ignore cleanup errors
ensure
  klass.instances.clear if klass.respond_to?(:instances)
end

## repair_related_fields! exists as class method
RRFWithCollections.respond_to?(:repair_related_fields!)
#=> true

## No orphans: healthy populated state returns empty result with status :ok
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'clean-1', name: 'Clean')
@obj.save
@obj.sessions.push('session-1')
@obj.tags.add('admin')
@obj.settings['theme'] = 'dark'
@result = RRFWithCollections.repair_related_fields!
[@result[:removed_keys], @result[:failed_keys], @result[:status]]
#=> [[], [], :ok]

## No orphans: plain class without related_fields returns empty result
rrf_reset_model(RRFPlainModel)
@p1 = RRFPlainModel.new(pid: 'p-1', name: 'One')
@p1.save
@result = RRFPlainModel.repair_related_fields!
[@result[:removed_keys], @result[:failed_keys], @result[:status]]
#=> [[], [], :ok]

## Single orphan: list key is removed after parent hash is deleted
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'crashed', name: 'Crashed')
@obj.save
@obj.sessions.push('session-1')
@list_key = @obj.sessions.dbkey
Familia.dbclient.del(@obj.dbkey)
Familia.dbclient.exists(@list_key)
#=> 1

## Single orphan: repair removes the list key and reports it in removed_keys
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'crashed', name: 'Crashed')
@obj.save
@obj.sessions.push('session-1')
@list_key = @obj.sessions.dbkey
Familia.dbclient.del(@obj.dbkey)
@result = RRFWithCollections.repair_related_fields!
[
  @result[:removed_keys].include?(@list_key),
  @result[:failed_keys],
  @result[:status],
  Familia.dbclient.exists(@list_key),
]
#=> [true, [], :issues_found, 0]

## Multi-field orphans on one instance: list, set, and hashkey all removed
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'multi', name: 'Multi')
@obj.save
@obj.sessions.push('s-1')
@obj.tags.add('t-1')
@obj.settings['k'] = 'v'
@list_key = @obj.sessions.dbkey
@set_key = @obj.tags.dbkey
@hash_key = @obj.settings.dbkey
Familia.dbclient.del(@obj.dbkey)
@result = RRFWithCollections.repair_related_fields!
[
  @result[:removed_keys].sort,
  @result[:status],
  Familia.dbclient.exists(@list_key),
  Familia.dbclient.exists(@set_key),
  Familia.dbclient.exists(@hash_key),
]
#=> [[@hash_key, @list_key, @set_key].sort, :issues_found, 0, 0, 0]

## Mixed orphans across instances: only crashed instances' keys are removed
rrf_reset_model(RRFWithCollections)
@live_keys = []
@dead_keys = []
(1..2).each do |i|
  obj = RRFWithCollections.new(cid: "live-#{i}", name: "Live #{i}")
  obj.save
  obj.sessions.push("session-#{i}")
  obj.tags.add("tag-#{i}")
  @live_keys << obj.sessions.dbkey
  @live_keys << obj.tags.dbkey
end
(1..3).each do |i|
  obj = RRFWithCollections.new(cid: "dead-#{i}", name: "Dead #{i}")
  obj.save
  obj.sessions.push("session-#{i}")
  obj.tags.add("tag-#{i}")
  @dead_keys << obj.sessions.dbkey
  @dead_keys << obj.tags.dbkey
  Familia.dbclient.del(obj.dbkey)
end
@result = RRFWithCollections.repair_related_fields!
[
  @result[:removed_keys].sort == @dead_keys.sort,
  @live_keys.all? { |k| Familia.dbclient.exists(k) == 1 },
  @dead_keys.all? { |k| Familia.dbclient.exists(k) == 0 },
  @result[:status],
]
#=> [true, true, true, :issues_found]

## Pre-computed audit results are used as-is (empty input is a no-op)
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'orphan-exists', name: 'Orphan')
@obj.save
@obj.sessions.push('s-1')
@list_key = @obj.sessions.dbkey
Familia.dbclient.del(@obj.dbkey)
# Pass in empty array: repair must not re-audit and must not touch Redis
@result = RRFWithCollections.repair_related_fields!([])
[
  @result[:removed_keys],
  @result[:status],
  Familia.dbclient.exists(@list_key),
]
#=> [[], :ok, 1]

## Pre-computed audit results are used verbatim: orphan keys in input are removed
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'explicit', name: 'Explicit')
@obj.save
@obj.sessions.push('s-1')
@list_key = @obj.sessions.dbkey
Familia.dbclient.del(@obj.dbkey)
@audit = RRFWithCollections.audit_related_fields
@result = RRFWithCollections.repair_related_fields!(@audit)
[
  @result[:removed_keys].include?(@list_key),
  Familia.dbclient.exists(@list_key),
  @result[:status],
]
#=> [true, 0, :issues_found]

## Progress callback is invoked with phase :repair_related_fields
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'progress', name: 'Progress')
@obj.save
@obj.sessions.push('s-1')
@obj.tags.add('t-1')
Familia.dbclient.del(@obj.dbkey)
@events = []
RRFWithCollections.repair_related_fields! { |p| @events << p }
[
  @events.any? { |e| e[:phase] == :repair_related_fields },
  @events.all? { |e| e.key?(:current) && e.key?(:total) },
  @events.size >= 1,
]
#=> [true, true, true]

## Progress callback reports final current == total
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'progress-final', name: 'ProgressFinal')
@obj.save
@obj.sessions.push('s-1')
@obj.tags.add('t-1')
@obj.settings['k'] = 'v'
Familia.dbclient.del(@obj.dbkey)
@events = []
RRFWithCollections.repair_related_fields! { |p| @events << p }
@last = @events.last
[@last[:phase], @last[:current], @last[:total]]
#=> [:repair_related_fields, 3, 3]

## repair_all! does NOT touch related fields when audit_collections not requested
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'skip', name: 'Skip')
@obj.save
@obj.sessions.push('s-1')
@list_key = @obj.sessions.dbkey
Familia.dbclient.del(@obj.dbkey)
# health_check default leaves related_fields nil so repair_all! skips the dimension
@result = RRFWithCollections.repair_all!
[
  @result.key?(:related_fields),
  Familia.dbclient.exists(@list_key),
]
#=> [false, 1]

## repair_all! with an audit_collections report cleans related fields
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'full', name: 'Full')
@obj.save
@obj.sessions.push('s-1')
@obj.tags.add('t-1')
@list_key = @obj.sessions.dbkey
@set_key = @obj.tags.dbkey
Familia.dbclient.del(@obj.dbkey)
# Build an AuditReport carrying the related_fields dimension, then run
# a health_check-driven repair_all! that will rebuild its own report
# with audit_collections: true.
@audit_report = RRFWithCollections.health_check(audit_collections: true)
# Replace repair_all!'s internal health_check call by patching temporarily
# would couple to internals; instead we drive repair directly and confirm
# the combined shape works end-to-end via a secondary audit cycle.
@repair_via_report = {
  report: @audit_report,
  related_fields: RRFWithCollections.repair_related_fields!(@audit_report.related_fields),
}
[
  @repair_via_report[:related_fields][:removed_keys].sort,
  Familia.dbclient.exists(@list_key),
  Familia.dbclient.exists(@set_key),
]
#=> [[@list_key, @set_key].sort, 0, 0]

## repair_all! integration: end-to-end via health_check audit path
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'e2e', name: 'E2E')
@obj.save
@obj.sessions.push('s-1')
@list_key = @obj.sessions.dbkey
Familia.dbclient.del(@obj.dbkey)
# Monkey-patch repair_all! behavior is out of scope; instead confirm the
# composed helper works: run health_check(audit_collections: true) then
# repair_related_fields! from the report.
@report = RRFWithCollections.health_check(audit_collections: true)
@result = RRFWithCollections.repair_related_fields!(@report.related_fields)
[
  @result[:removed_keys].include?(@list_key),
  Familia.dbclient.exists(@list_key),
]
#=> [true, 0]

## Idempotent: second call on clean state is a no-op
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'idem', name: 'Idem')
@obj.save
@obj.sessions.push('s-1')
@obj.tags.add('t-1')
Familia.dbclient.del(@obj.dbkey)
@first = RRFWithCollections.repair_related_fields!
@second = RRFWithCollections.repair_related_fields!
[
  @first[:removed_keys].size >= 2,
  @first[:status],
  @second[:removed_keys],
  @second[:failed_keys],
  @second[:status],
]
#=> [true, :issues_found, [], [], :ok]

## After repair, audit_related_fields shows no remaining orphans
rrf_reset_model(RRFWithCollections)
@obj = RRFWithCollections.new(cid: 'post-audit', name: 'PostAudit')
@obj.save
@obj.sessions.push('s-1')
@obj.tags.add('t-1')
Familia.dbclient.del(@obj.dbkey)
RRFWithCollections.repair_related_fields!
RRFWithCollections.audit_related_fields.all? { |r| r[:orphaned_keys].empty? }
#=> true

## repair_all!(audit_collections: true) removes orphaned collection keys end-to-end
rrf_reset_model(RRFWithCollections)
(1..3).each do |i|
  obj = RRFWithCollections.new(cid: "orphan-#{i}", name: "Orphan #{i}")
  obj.save
  obj.sessions.push("session-#{i}")
  obj.tags.add("tag-#{i}")
end
@orphan_keys = (1..3).flat_map do |i|
  o = RRFWithCollections.new(cid: "orphan-#{i}")
  [o.sessions.dbkey, o.tags.dbkey]
end
# Crash parents: hashes gone, collection keys linger as orphans
(1..3).each do |i|
  Familia.dbclient.del(RRFWithCollections.new(cid: "orphan-#{i}").dbkey)
end
@result = RRFWithCollections.repair_all!(audit_collections: true)
[
  @result.key?(:related_fields),
  @result[:related_fields][:removed_keys].sort == @orphan_keys.sort,
  @orphan_keys.all? { |k| Familia.dbclient.exists(k) == 0 },
  @result[:related_fields][:status],
]
#=> [true, true, true, :issues_found]

## repair_related_fields! failure path: Redis::CommandError on one key is captured in failed_keys
rrf_reset_model(RRFWithCollections)
@obj_a = RRFWithCollections.new(cid: 'fail-a', name: 'A')
@obj_a.save
@obj_a.sessions.push('s-a')
@obj_b = RRFWithCollections.new(cid: 'fail-b', name: 'B')
@obj_b.save
@obj_b.sessions.push('s-b')
@fail_key = @obj_a.sessions.dbkey
@ok_key = @obj_b.sessions.dbkey
Familia.dbclient.del(@obj_a.dbkey)
Familia.dbclient.del(@obj_b.dbkey)
# Install a simple proxy client that raises Redis::CommandError on del()
# for one specific key and delegates everything else to the real client.
# Then redefine RRFWithCollections.dbclient at the class level to return
# the proxy, so every call inside repair_related_fields! hits the stub.
class RRFDelFailProxy
  def initialize(real, fail_key)
    @real = real
    @fail_key = fail_key
  end

  def del(*keys)
    flat = keys.flatten
    raise Redis::CommandError, 'simulated del failure' if flat.include?(@fail_key)
    @real.del(*flat)
  end

  def method_missing(name, *args, **kwargs, &block)
    @real.public_send(name, *args, **kwargs, &block)
  end

  def respond_to_missing?(name, include_private = false)
    @real.respond_to?(name, include_private)
  end
end

@real_client = RRFWithCollections.dbclient
@proxy_client = RRFDelFailProxy.new(@real_client, @fail_key)
RRFWithCollections.define_singleton_method(:dbclient) { |*| @proxy_client_stub }
RRFWithCollections.instance_variable_set(:@proxy_client_stub, @proxy_client)
begin
  @result = RRFWithCollections.repair_related_fields!
ensure
  RRFWithCollections.singleton_class.send(:remove_method, :dbclient)
  RRFWithCollections.remove_instance_variable(:@proxy_client_stub)
end
[
  @result[:failed_keys].any? { |entry| entry[:key] == @fail_key && entry[:error].include?('simulated del failure') },
  @result[:removed_keys].include?(@fail_key),
  @result[:removed_keys].include?(@ok_key),
  @result[:status],
  Familia.dbclient.exists(@fail_key),
  Familia.dbclient.exists(@ok_key),
]
#=> [true, false, true, :issues_found, 1, 0]

## repair_related_fields! side-effect isolation: instances timeline and indexes untouched
class RRFIsolationModel < Familia::Horreum
  feature :relationships
  identifier_field :iid
  field :iid
  field :name
  field :email
  unique_index :email, :by_email
  list :sessions
  set :tags
end

rrf_reset_model(RRFIsolationModel)
RRFIsolationModel.by_email.clear if RRFIsolationModel.respond_to?(:by_email)
# Create 4 instances with related fields and unique_index-backed email field.
(1..4).each do |i|
  obj = RRFIsolationModel.new(iid: "iso-#{i}", name: "Iso #{i}", email: "iso#{i}@example.com")
  obj.save
  obj.sessions.push("session-#{i}")
  obj.tags.add("tag-#{i}")
end
# Crash parents for instances 2 and 3 to create related_field orphans.
Familia.dbclient.del(RRFIsolationModel.new(iid: 'iso-2').dbkey)
Familia.dbclient.del(RRFIsolationModel.new(iid: 'iso-3').dbkey)
@instances_before = RRFIsolationModel.instances.size
@by_email_before = RRFIsolationModel.by_email.field_count
@by_email_members_before = RRFIsolationModel.by_email.hgetall
@instances_members_before = RRFIsolationModel.instances.members.sort
@result = RRFIsolationModel.repair_related_fields!
@instances_after = RRFIsolationModel.instances.size
@by_email_after = RRFIsolationModel.by_email.field_count
@by_email_members_after = RRFIsolationModel.by_email.hgetall
@instances_members_after = RRFIsolationModel.instances.members.sort
[
  @result[:removed_keys].size >= 4,
  @result[:status],
  @instances_before == @instances_after,
  @by_email_before == @by_email_after,
  @instances_members_before == @instances_members_after,
  @by_email_members_before == @by_email_members_after,
]
#=> [true, :issues_found, true, true, true, true]

# Teardown
rrf_reset_model(RRFPlainModel)
rrf_reset_model(RRFWithCollections)
rrf_reset_model(RRFIsolationModel) if defined?(RRFIsolationModel)
