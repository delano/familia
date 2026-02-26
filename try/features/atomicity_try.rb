require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Dedicated test model for atomicity tests
class AtomicTestPlan < Familia::Horreum
  identifier_field :planid
  field :planid
  field :region
  field :tier
  set :features
  list :audit_log
end

# Clean slate
AtomicTestPlan.instances.clear
AtomicTestPlan.all.each(&:destroy!)

## Scalar field change is in-memory only until save
@plan = AtomicTestPlan.new(planid: 'atom_plan1', region: 'US')
@plan.save
@plan.region = 'UK'
@stored = AtomicTestPlan.find_by_id('atom_plan1')
@stored.region
#=> 'US'

## After save, scalar change is persisted
@plan.save
@stored2 = AtomicTestPlan.find_by_id('atom_plan1')
@stored2.region
#=> 'UK'

## Collection write is immediate even without save
@plan2 = AtomicTestPlan.new(planid: 'atom_plan2', region: 'EU')
@plan2.save
@plan2.features.add('basic')
@plan2.features.member?('basic')
#=> true

## Collection write persists while scalar change does not
@plan3 = AtomicTestPlan.new(planid: 'atom_plan3', region: 'US')
@plan3.save
@plan3.region = 'JP'
@plan3.features.add('premium')
@reloaded = AtomicTestPlan.find_by_id('atom_plan3')
[@reloaded.region, @reloaded.features.member?('premium')]
#=> ['US', true]

## fast_writer persists scalar immediately unlike normal setter
@plan4 = AtomicTestPlan.new(planid: 'atom_plan4', region: 'US')
@plan4.save
@plan4.region! 'DE'
@fast_stored = AtomicTestPlan.find_by_id('atom_plan4')
@fast_stored.region
#=> 'DE'

## Collection clear is immediate (no MULTI with scalars)
@plan5 = AtomicTestPlan.new(planid: 'atom_plan5', region: 'US')
@plan5.save
@plan5.features.add('feature_a')
@plan5.features.add('feature_b')
@plan5.features.clear
@plan5.features.members
#=> []

## persist_to_storage writes all hash fields atomically in a transaction
@plan6 = AtomicTestPlan.new(planid: 'atom_plan6', region: 'CA', tier: 'gold')
@plan6.save
@stored6 = AtomicTestPlan.find_by_id('atom_plan6')
[@stored6.region, @stored6.tier]
#=> ['CA', 'gold']

## commit_fields now registers via ensure_registered!
@plan7 = AtomicTestPlan.new(planid: 'atom_plan7', region: 'AU')
@plan7.commit_fields
AtomicTestPlan.instances.member?('atom_plan7')
#=> true

## unregister! removes object from instances sorted set
@plan7.unregister!
AtomicTestPlan.instances.member?('atom_plan7')
#=> false

## save_with_collections preserves ordering: scalars then collections
@plan8 = AtomicTestPlan.new(planid: 'atom_plan8', region: 'FR')
@plan8.save_with_collections do
  @plan8.features.add('enterprise')
  @plan8.audit_log.push('created')
end
@loaded8 = AtomicTestPlan.find_by_id('atom_plan8')
[@loaded8.region, @plan8.features.member?('enterprise'), @plan8.audit_log.members]
#=> ['FR', true, ['created']]

## dirty? returns true after setter, false after save
@plan9 = AtomicTestPlan.new(planid: 'atom_plan9', region: 'BR')
@plan9.save
@clean = @plan9.dirty?
@plan9.region = 'MX'
@dirty = @plan9.dirty?
@plan9.save
@after_save = @plan9.dirty?
[@clean, @dirty, @after_save]
#=> [false, true, false]

## dirty? with field name checks specific field
@plan10 = AtomicTestPlan.new(planid: 'atom_plan10', region: 'IN')
@plan10.save
@plan10.region = 'CN'
[@plan10.dirty?(:region), @plan10.dirty?(:tier)]
#=> [true, false]

## changed_fields tracks old and new values
@plan11 = AtomicTestPlan.new(planid: 'atom_plan11', region: 'KR')
@plan11.save
@plan11.region = 'SG'
@changes = @plan11.changed_fields
[@changes[:region][0], @changes[:region][1]]
#=> ['KR', 'SG']

## registered? class method checks instances sorted set
@plan12 = AtomicTestPlan.new(planid: 'atom_plan12', region: 'NZ')
@before = AtomicTestPlan.registered?('atom_plan12')
@plan12.save
@after = AtomicTestPlan.registered?('atom_plan12')
[@before, @after]
#=> [false, true]

## batch_update registers in instances sorted set
@plan13 = AtomicTestPlan.new(planid: 'atom_plan13', region: 'ZA')
@plan13.save
@plan13.batch_update(region: 'NG')
@reloaded13 = AtomicTestPlan.find_by_id('atom_plan13')
[@reloaded13.region, AtomicTestPlan.registered?('atom_plan13')]
#=> ['NG', true]

# Cleanup
AtomicTestPlan.instances.clear
AtomicTestPlan.all.each(&:destroy!)
