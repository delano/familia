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

## Instance responds to do_chore!
@org.respond_to?(:do_chore!)
#=> true

## Instance responds to do_chores!
@org.respond_to?(:do_chores!)
#=> true

## Instance responds to tidy! (alias for do_chores!)
@org.respond_to?(:tidy!)
#=> true

## tidy! is an alias of do_chores! (same method, not a wrapper)
@org.method(:tidy!) == @org.method(:do_chores!)
#=> true

## Chores are registered in declaration order
HousekeepingOrg.chores.keys
#=> [:standardize_planid, :uppercase_country]

## do_chores! runs every registered chore and returns a Hash
results = @org.do_chores!
results.keys.sort
#=> [:standardize_planid, :uppercase_country]

## do_chores! persists changes via the block (planid normalized)
@org.refresh!
@org.planid
#=> "professional"

## do_chores! persists changes via the block (country uppercased)
@org.country
#=> "US"

## A second do_chores! is a no-op (idempotent by convention)
second = @org.do_chores!
second
#=> {:standardize_planid=>nil, :uppercase_country=>nil}

## tidy! delegates to do_chores! and returns the same Hash shape
tidy_results = @org.tidy!
tidy_results
#=> {:standardize_planid=>nil, :uppercase_country=>nil}

## do_chore! runs only the named chore and returns the block's raw value
@org2 = HousekeepingOrg.new(orgid: 'beta', planid: 'free', country: 'ca')
@org2.save
@org2.do_chore!(:uppercase_country)
#=> true

## do_chore! accepts a String name as well as a Symbol
@org3 = HousekeepingOrg.new(orgid: 'gamma', planid: 'free', country: 'mx')
@org3.save
@org3.do_chore!('uppercase_country')
#=> true

## Other chores are not run when do_chore! is called by name
@org2.refresh!
@org2.planid # untouched (still 'free' which case maps to 'free' so no change)
#=> "free"

## do_chore! returns the raw value when the block returns a no-op (nil)
@org2.do_chore!(:standardize_planid)
#=> nil

## do_chore! with unknown chore raises ArgumentError
begin
  @org.do_chore!(:nonexistent)
rescue ArgumentError => e
  e.message
end
#=> "unknown chore :nonexistent"

## do_chore! with nil name raises ArgumentError
begin
  @org.do_chore!(nil)
rescue ArgumentError => e
  e.message
end
#=> "chore name required"

## do_chore! with empty name raises ArgumentError
begin
  @org.do_chore!('')
rescue ArgumentError => e
  e.message
end
#=> "chore name required"

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

## A class with no chores returns an empty hash from do_chores!
@noop = HousekeepingNoop.new(id: 'x')
@noop.do_chores!
#=> {}

## tidy! on a class with no chores also returns an empty hash
@noop.tidy!
#=> {}

## tidy! no longer accepts a name argument (was a single-arg form in 2.7.0)
begin
  @org.tidy!(:standardize_planid)
rescue ArgumentError => e
  e.message.include?('wrong number of arguments')
end
#=> true

## chore registration is per-class (HousekeepingNoop has no chores)
HousekeepingNoop.chores
#=> {}

## Errors raised in a chore propagate to the caller via do_chores!
class HousekeepingRaise < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id
  chore(:boom) { |_| raise 'kaboom' }
end
@raiser = HousekeepingRaise.new(id: 'r')
@raiser.save
begin
  @raiser.do_chores!
rescue RuntimeError => e
  e.message
end
#=> "kaboom"

## Errors raised in a chore propagate to the caller via do_chore!
begin
  @raiser.do_chore!(:boom)
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
@rep.do_chores!
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
@child.do_chores!.keys.sort
#=> [:from_child, :from_parent]

## Subclass can override a parent chore by re-registering the same name
class HousekeepingOverride < HousekeepingParent
  chore(:from_parent) { |_o| :overridden }
end
HousekeepingOverride.chores.keys
#=> [:from_parent]

## do_chore! on subclass runs the override block, not the parent block
@override = HousekeepingOverride.new(id: 'ov')
@override.save
@override.do_chore!(:from_parent)
#=> :overridden

## Parent registry is unchanged by a subclass override
HousekeepingParent.chores[:from_parent].equal?(HousekeepingOverride.chores[:from_parent])
#=> false

## Cleanup
@org.destroy! if @org.exists?
@org2.destroy! if @org2.exists?
@org3.destroy! if @org3.exists?
@noop.destroy! if @noop.exists?
@raiser.destroy! if @raiser.exists?
@rep.destroy! if @rep.exists?
@child.destroy! if @child.exists?
@override.destroy! if @override.exists?
true
#=> true
