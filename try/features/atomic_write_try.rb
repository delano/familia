require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Primary test class for atomic_write behavior
class AtomicWriteTestPlan < Familia::Horreum
  identifier_field :planid
  field :planid
  field :name
  field :region
  field :tier
  set :features
  sorted_set :scores
  hashkey :settings
  list :audit_log
end

# Class with expiration feature for TTL test
class AtomicWriteExpiringPlan < Familia::Horreum
  feature :expiration
  identifier_field :planid
  field :planid
  field :name
  default_expiration 3600
  set :tags
end

# Class with a cross-database collection for CrossDatabaseError test
class AtomicWriteCrossDbPlan < Familia::Horreum
  logical_database 0
  identifier_field :planid
  field :planid
  field :name
  list :items, logical_database: 5
end

# Class with a cross-database CLASS-LEVEL collection. Exercises the guard's
# ability to catch class_related_fields (e.g. class_sorted_set, class_list)
# on a different logical_database than the parent Horreum. This matters
# because persist_to_storage writes to self.class.instances inside the MULTI.
class AtomicWriteCrossDbClassPlan < Familia::Horreum
  logical_database 0
  identifier_field :planid
  field :planid
  field :name
  class_sorted_set :leaderboard, logical_database: 6
end

# Clean slate
AtomicWriteTestPlan.instances.clear
AtomicWriteTestPlan.all.each(&:destroy!)
AtomicWriteExpiringPlan.instances.clear
AtomicWriteExpiringPlan.all.each(&:destroy!)
# CrossDb cleanup is best-effort; destroying is risky across DBs
AtomicWriteCrossDbPlan.instances.clear rescue nil

## atomic_write persists scalar and collection changes atomically
@plan_a = AtomicWriteTestPlan.new(planid: 'aw_plan_a', name: 'Basic', region: 'US')
@plan_a.save
@plan_a.atomic_write do
  @plan_a.name = 'Premium'
  @plan_a.region = 'UK'
  @plan_a.features.add('sso')
  @plan_a.features.add('priority')
  @plan_a.scores.add('metric_a', 42.0)
  @plan_a.scores.add('metric_b', 99.5)
  @plan_a.settings['theme'] = 'dark'
  @plan_a.settings['lang'] = 'en'
  @plan_a.audit_log.push('upgraded')
end
@reloaded_a = AtomicWriteTestPlan.find_by_id('aw_plan_a')
[
  @reloaded_a.name,
  @reloaded_a.region,
  @reloaded_a.features.members.sort,
  @reloaded_a.scores.members.sort,
  @reloaded_a.settings['theme'],
  @reloaded_a.settings['lang'],
  @reloaded_a.audit_log.members,
]
#=> ['Premium', 'UK', ['priority', 'sso'], ['metric_a', 'metric_b'], 'dark', 'en', ['upgraded']]

## atomic_write with scalar-only block still saves
@plan_b = AtomicWriteTestPlan.new(planid: 'aw_plan_b', name: 'Initial', region: 'EU')
result_b = @plan_b.atomic_write do
  @plan_b.name = 'Scalar-only Update'
  @plan_b.region = 'JP'
end
@reloaded_b = AtomicWriteTestPlan.find_by_id('aw_plan_b')
[result_b, @reloaded_b.name, @reloaded_b.region]
#=> [true, 'Scalar-only Update', 'JP']

## atomic_write with collections-only block (after prior save)
@plan_c = AtomicWriteTestPlan.new(planid: 'aw_plan_c', name: 'Stable', region: 'US')
@plan_c.save
@plan_c.atomic_write do
  @plan_c.features.add('analytics')
  @plan_c.audit_log.push('collections_only')
end
@reloaded_c = AtomicWriteTestPlan.find_by_id('aw_plan_c')
[@reloaded_c.name, @reloaded_c.features.members, @reloaded_c.audit_log.members]
#=> ['Stable', ['analytics'], ['collections_only']]

## atomic_write with empty block still persists current scalar state
@plan_d = AtomicWriteTestPlan.new(planid: 'aw_plan_d', name: 'Old Name')
@plan_d.save
@plan_d.name = 'New Name'
@plan_d.atomic_write { }
AtomicWriteTestPlan.find_by_id('aw_plan_d').name
#=> 'New Name'

## atomic_write returns true on successful commit
@plan_e = AtomicWriteTestPlan.new(planid: 'aw_plan_e', name: 'ReturnValueTest')
@plan_e.atomic_write { @plan_e.features.add('x') }
#=> true

## atomic_write clear-then-add sequence executes atomically
@plan_f = AtomicWriteTestPlan.new(planid: 'aw_plan_f', name: 'ClearThenAdd')
@plan_f.save
@plan_f.features.add('old_a')
@plan_f.features.add('old_b')
@plan_f.atomic_write do
  @plan_f.features.clear
  @plan_f.features.add('new_a')
  @plan_f.features.add('new_b')
end
@reloaded_f = AtomicWriteTestPlan.find_by_id('aw_plan_f')
@reloaded_f.features.members.sort
#=> ['new_a', 'new_b']

## dirty? is false after successful atomic_write
@plan_g = AtomicWriteTestPlan.new(planid: 'aw_plan_g', name: 'DirtyCheck')
@plan_g.save
@plan_g.atomic_write do
  @plan_g.name = 'Changed'
  @plan_g.region = 'FR'
end
@plan_g.dirty?
#=> false

## atomic_write raises OperationModeError when nested inside transaction { }
@plan_h = AtomicWriteTestPlan.new(planid: 'aw_plan_h', name: 'NestedInTxn')
@plan_h.save
begin
  Familia.transaction do
    @plan_h.atomic_write { @plan_h.name = 'Should fail' }
  end
  :no_raise
rescue Familia::OperationModeError => e
  :raised
end
#=> :raised

## atomic_write raises OperationModeError when nested inside another atomic_write
@plan_i = AtomicWriteTestPlan.new(planid: 'aw_plan_i', name: 'NestedInAtomic')
@plan_i.save
begin
  @plan_i.atomic_write do
    @plan_i.name = 'Outer'
    @plan_i.atomic_write { @plan_i.name = 'Inner' }
  end
  :no_raise
rescue Familia::OperationModeError => e
  :raised
end
#=> :raised

## atomic_write raises CrossDatabaseError for a field on a different logical_database
@plan_j = AtomicWriteCrossDbPlan.new(planid: 'aw_plan_j', name: 'CrossDb')
begin
  @plan_j.atomic_write { @plan_j.name = 'Should fail' }
  :no_raise
rescue Familia::CrossDatabaseError => e
  [:raised, e.field_name, e.field_database, e.horreum_database]
end
#=> [:raised, :items, 5, 0]

## exception inside atomic_write block prevents commit
@plan_k = AtomicWriteTestPlan.new(planid: 'aw_plan_k', name: 'Original', region: 'US')
@plan_k.save
@plan_k.features.add('keep_me')
begin
  @plan_k.atomic_write do
    @plan_k.name = 'Should not persist'
    @plan_k.features.add('should_not_persist')
    raise 'boom'
  end
rescue RuntimeError
  # expected
end
@reloaded_k = AtomicWriteTestPlan.find_by_id('aw_plan_k')
[@reloaded_k.name, @reloaded_k.features.members.sort]
#=> ['Original', ['keep_me']]

## atomic_write raises ArgumentError when called without a block
@plan_l = AtomicWriteTestPlan.new(planid: 'aw_plan_l', name: 'NoBlock')
begin
  @plan_l.atomic_write
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

## update_expiration: false suppresses TTL command
@plan_m = AtomicWriteExpiringPlan.new(planid: 'aw_plan_m', name: 'TtlTest')
@plan_m.save
# Explicitly remove any TTL so we can verify atomic_write(update_expiration: false)
# does not set a new one.
Familia.dbclient.persist(@plan_m.dbkey)
ttl_before = Familia.dbclient.ttl(@plan_m.dbkey)
@plan_m.atomic_write(update_expiration: false) do
  @plan_m.name = 'NoTtlApplied'
end
ttl_after = Familia.dbclient.ttl(@plan_m.dbkey)
# -1 means key exists with no expiration
[ttl_before, ttl_after]
#=> [-1, -1]

## instances sorted set is updated after atomic_write
@plan_n = AtomicWriteTestPlan.new(planid: 'aw_plan_n', name: 'InstancesTest')
@plan_n.atomic_write { @plan_n.region = 'CA' }
AtomicWriteTestPlan.in_instances?('aw_plan_n')
#=> true

## save_with_collections still works (regression)
@plan_o = AtomicWriteTestPlan.new(planid: 'aw_plan_o', name: 'SaveWithColl')
@plan_o.save_with_collections do
  @plan_o.features.add('regression_a')
  @plan_o.features.add('regression_b')
end
@reloaded_o = AtomicWriteTestPlan.find_by_id('aw_plan_o')
[@reloaded_o.name, @reloaded_o.features.members.sort]
#=> ['SaveWithColl', ['regression_a', 'regression_b']]

## warn_if_dirty! is suppressed during atomic_write block
@plan_p = AtomicWriteTestPlan.new(planid: 'aw_plan_p', name: 'Original')
@plan_p.save
# Capture warnings emitted via Familia.warn (goes to stderr by default)
original_stderr = $stderr
$stderr = StringIO.new
begin
  @plan_p.atomic_write do
    @plan_p.name = 'Dirty!'           # Makes parent dirty
    @plan_p.features.add('collection_while_dirty')  # Would normally warn
    @plan_p.settings['k'] = 'v'       # Another warn_if_dirty! path
    @plan_p.audit_log.push('entry')   # Another warn_if_dirty! path
  end
  captured = $stderr.string
ensure
  $stderr = original_stderr
end
# No warning should contain the "unsaved scalar fields" message
captured.include?('unsaved scalar fields')
#=> false

## collection writes inside atomic_write land in the same MULTI/EXEC as scalars
@plan_q = AtomicWriteTestPlan.new(planid: 'aw_plan_q', name: 'FutureTest')
@plan_q.save
@plan_q.features.add('outside_val')  # immediate, non-transaction
@plan_q.atomic_write do
  @plan_q.name = 'FutureTest-updated'
  @plan_q.features.add('inside_val')
end
# Reload and confirm both the scalar change and the in-block collection mutation landed
@plan_q_reloaded = AtomicWriteTestPlan.load('aw_plan_q')
[@plan_q_reloaded.name, @plan_q_reloaded.features.members.sort]
#=> ["FutureTest-updated", ["inside_val", "outside_val"]]

## two Fibers running atomic_write on different instances do not cross-contaminate state
@plan_r1 = AtomicWriteTestPlan.new(planid: 'aw_plan_r1', name: 'FiberA-Initial')
@plan_r1.save
@plan_r2 = AtomicWriteTestPlan.new(planid: 'aw_plan_r2', name: 'FiberB-Initial')
@plan_r2.save

@fiber_a = Fiber.new do
  @plan_r1.atomic_write do
    @plan_r1.name = 'FiberA-Final'
    @plan_r1.features.add('a1')
    Fiber.yield :a_paused
    @plan_r1.features.add('a2')
  end
  :a_done
end

@fiber_b = Fiber.new do
  @plan_r2.atomic_write do
    @plan_r2.name = 'FiberB-Final'
    @plan_r2.features.add('b1')
    @plan_r2.features.add('b2')
  end
  :b_done
end

@fiber_a.resume          # starts A's atomic_write, pauses mid-block
@fiber_b.resume          # runs B's atomic_write to completion
@fiber_a.resume          # resumes A, completes atomic_write

@r1_reloaded = AtomicWriteTestPlan.find_by_id('aw_plan_r1')
@r2_reloaded = AtomicWriteTestPlan.find_by_id('aw_plan_r2')
[
  @r1_reloaded.name,
  @r1_reloaded.features.members.sort,
  @r2_reloaded.name,
  @r2_reloaded.features.members.sort,
]
#=> ['FiberA-Final', ['a1', 'a2'], 'FiberB-Final', ['b1', 'b2']]

## atomic_write raises CrossDatabaseError for a CLASS-LEVEL field on a different logical_database
## Guard must inspect class_related_fields (e.g. class_sorted_set) in addition to related_fields,
## because persist_to_storage writes to self.class.instances inside the MULTI.
@plan_s = AtomicWriteCrossDbClassPlan.new(planid: 'aw_plan_s', name: 'ClassCrossDb')
begin
  @plan_s.atomic_write { @plan_s.name = 'Should fail' }
  :no_raise
rescue Familia::CrossDatabaseError => e
  [:raised, e.field_name, e.field_database, e.horreum_database]
end
#=> [:raised, :leaderboard, 6, 0]

## same-instance atomic_write across two Fibers: both proceed without a re-entrancy error
## KNOWN LIMITATION: @atomic_write_active is an instance ivar shared across Fibers, but
## Fiber[:familia_transaction] is Fiber-local. So Fiber B's nested-transaction guard does
## not fire even though Fiber A has an active MULTI on the same instance. Each Fiber opens
## its own MULTI/EXEC on its own pool connection. This test pins down the observable outcome:
## both transactions commit, the last-writer-wins for scalar fields, and set members from
## both Fibers accumulate on the shared Redis key. Documented here so any future change to
## add re-entrancy protection will break this test intentionally.
@plan_t = AtomicWriteTestPlan.new(planid: 'aw_plan_t', name: 'SameInstance-Initial')
@plan_t.save

@fiber_same_a = Fiber.new do
  @plan_t.atomic_write do
    @plan_t.name = 'FiberA-Wrote'
    @plan_t.features.add('shared_a')
    Fiber.yield :a_paused_inside_multi
    @plan_t.features.add('shared_a2')
  end
  :a_done
end

@fiber_same_b = Fiber.new do
  begin
    @plan_t.atomic_write do
      @plan_t.name = 'FiberB-Wrote'
      @plan_t.features.add('shared_b')
    end
    :b_done
  rescue Familia::OperationModeError, Familia::PersistenceError => e
    [:b_raised, e.class.name]
  end
end

@fiber_same_a.resume  # A enters atomic_write, opens MULTI, yields mid-block
@fiber_b_result = @fiber_same_b.resume  # B enters atomic_write on same instance; current behavior: runs independently
@fiber_a_result = @fiber_same_a.resume  # A resumes and completes

@t_reloaded = AtomicWriteTestPlan.find_by_id('aw_plan_t')
# Both Fibers completed without raising (existing behavior, no same-instance re-entrancy guard).
# Features from both Fibers are present on the shared key.
[
  @fiber_a_result,
  @fiber_b_result,
  ['shared_a', 'shared_a2', 'shared_b'].all? { |m| @t_reloaded.features.member?(m) },
]
#=> [:a_done, :b_done, true]

# Cleanup
AtomicWriteTestPlan.instances.clear
AtomicWriteTestPlan.all.each(&:destroy!)
AtomicWriteExpiringPlan.instances.clear
AtomicWriteExpiringPlan.all.each(&:destroy!)
AtomicWriteCrossDbPlan.instances.clear rescue nil
AtomicWriteCrossDbClassPlan.instances.clear rescue nil
AtomicWriteCrossDbClassPlan.leaderboard.clear rescue nil
