# try/features/housekeeping/housekeeping_try.rb
#
# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

class HousekeepingOrg < Familia::Horreum
  feature :housekeeping

  identifier_field :orgid
  field :orgid
  field :planid
  field :country

  chore :standardize_planid do |org|
    canonical = case org.planid
                when 'pro', 'Pro', 'professional_v1' then 'professional'
                when 'free', 'Free', 'basic'         then 'free'
                end
    if canonical && canonical != org.planid
      org.planid = canonical
      org.save
      true
    end
  end

  chore :uppercase_country do |org|
    next unless org.country && org.country != org.country.upcase
    org.country = org.country.upcase
    org.save
    true
  end
end

class HousekeepingNoop < Familia::Horreum
  feature :housekeeping

  identifier_field :id
  field :id
end

@org = HousekeepingOrg.new(orgid: 'acme', planid: 'Pro', country: 'us')
@org.save

## Class responds to chore registration DSL
HousekeepingOrg.respond_to?(:chore)
#=> true

## Class responds to chores reader
HousekeepingOrg.respond_to?(:chores)
#=> true

## Instance responds to tidy!
@org.respond_to?(:tidy!)
#=> true

## Chores are registered in declaration order
HousekeepingOrg.chores.keys
#=> [:standardize_planid, :uppercase_country]

## tidy! with no args runs every registered chore and returns a Hash
results = @org.tidy!
results.keys.sort
#=> [:standardize_planid, :uppercase_country]

## tidy! persists changes via the block (planid normalized)
@org.refresh!
@org.planid
#=> "professional"

## tidy! persists changes via the block (country uppercased)
@org.country
#=> "US"

## A second tidy! is a no-op (idempotent by convention)
second = @org.tidy!
second
#=> {:standardize_planid=>nil, :uppercase_country=>nil}

## tidy! with a name runs only that chore
@org2 = HousekeepingOrg.new(orgid: 'beta', planid: 'free', country: 'ca')
@org2.save
result = @org2.tidy!(:uppercase_country)
result
#=> {:uppercase_country=>true}

## Other chores are not run when called by name
@org2.refresh!
@org2.planid # untouched (still 'free' which case maps to 'free' so no change)
#=> "free"

## tidy! with unknown chore raises ArgumentError
begin
  @org.tidy!(:nonexistent)
rescue ArgumentError => e
  e.message
end
#=> "unknown chore :nonexistent"

## chore registered without a block raises
begin
  HousekeepingOrg.chore(:no_block)
rescue ArgumentError => e
  e.message
end
#=> "chore :no_block requires a block"

## chore registered with empty name raises
begin
  HousekeepingOrg.chore('') { |_| true }
rescue ArgumentError => e
  e.message
end
#=> "chore name required"

## A class with no chores returns an empty hash from tidy!
@noop = HousekeepingNoop.new(id: 'x')
@noop.tidy!
#=> {}

## chore registration is per-class (HousekeepingNoop has no chores)
HousekeepingNoop.chores
#=> {}

## Errors raised in a chore propagate to the caller
class HousekeepingRaise < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id
  chore(:boom) { |_| raise 'kaboom' }
end
@raiser = HousekeepingRaise.new(id: 'r')
@raiser.save
begin
  @raiser.tidy!
rescue RuntimeError => e
  e.message
end
#=> "kaboom"

## Re-registering a chore with the same name overwrites the previous block
class HousekeepingReplace < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id
  field :stamp
  chore(:mark) { |o| o.stamp = 'first';  o.save; :first }
  chore(:mark) { |o| o.stamp = 'second'; o.save; :second }
end
@rep = HousekeepingReplace.new(id: 'r')
@rep.save
@rep.tidy!
#=> {:mark=>:second}

## Subclasses inherit chores from their parent (copy-on-access)
class HousekeepingParent < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id
  field :stamp
  chore(:from_parent) { |o| o.stamp = 'parent'; o.save; :parent }
end
class HousekeepingChild < HousekeepingParent
  chore(:from_child) { |o| o.stamp = 'child'; o.save; :child }
end
HousekeepingChild.chores.keys.sort
#=> [:from_child, :from_parent]

## Registering on the child does not mutate the parent's chores
HousekeepingParent.chores.keys
#=> [:from_parent]

## Inherited chores run alongside child-specific ones
@child = HousekeepingChild.new(id: 'c')
@child.save
@child.tidy!.keys.sort
#=> [:from_child, :from_parent]

## Cleanup
@org.destroy! if @org.exists?
@org2.destroy! if @org2.exists?
@noop.destroy! if @noop.exists?
@raiser.destroy! if @raiser.exists?
@rep.destroy! if @rep.exists?
@child.destroy! if @child.exists?
true
#=> true
