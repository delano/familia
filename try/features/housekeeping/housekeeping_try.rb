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

## run_chores! returns model name, scanned count, and per-chore stats
class HousekeepingBulk < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id
  field :code

  chore :uppercase_code do |obj|
    next unless obj.code && obj.code != obj.code.upcase
    obj.code = obj.code.upcase
    obj.save
    true
  end
end
@bulk1 = HousekeepingBulk.new(id: 'b1', code: 'aaa'); @bulk1.save
@bulk2 = HousekeepingBulk.new(id: 'b2', code: 'BBB'); @bulk2.save
@bulk3 = HousekeepingBulk.new(id: 'b3', code: 'ccc'); @bulk3.save
@bulk_result = HousekeepingBulk.run_chores!
[@bulk_result[:model], @bulk_result[:scanned]]
#=> [HousekeepingBulk.name, 3]

## run_chores! per-chore stats count modifications (truthy returns)
@bulk_result[:chores][:uppercase_code]
#=> {modified: 2, errors: 0}

## run_chores! actually persists changes
HousekeepingBulk.find_by_identifier('b1').code
#=> "AAA"

## run_chores! with chore_name: filters to a single chore
class HousekeepingBulkMulti < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id
  field :name
  field :country

  chore(:strip_name) { |o| o.name && o.name != o.name.strip ? (o.name = o.name.strip; o.save; true) : nil }
  chore(:upper_country) { |o| o.country && o.country != o.country.upcase ? (o.country = o.country.upcase; o.save; true) : nil }
end
@m1 = HousekeepingBulkMulti.new(id: 'm1', name: '  alice  ', country: 'us'); @m1.save
@m2 = HousekeepingBulkMulti.new(id: 'm2', name: 'bob',       country: 'ca'); @m2.save
HousekeepingBulkMulti.run_chores!(chore_name: :upper_country)[:chores].keys
#=> [:upper_country]

## run_chores! with chore_name does not run the other chore
HousekeepingBulkMulti.find_by_identifier('m1').name
#=> "  alice  "

## run_chores! with chore_name actually ran the named chore
HousekeepingBulkMulti.find_by_identifier('m1').country
#=> "US"

## run_chores! honors limit
@m3 = HousekeepingBulkMulti.new(id: 'm3', name: 'carol', country: 'mx'); @m3.save
@m4 = HousekeepingBulkMulti.new(id: 'm4', name: 'dave',  country: 'br'); @m4.save
HousekeepingBulkMulti.run_chores!(chore_name: :upper_country, limit: 2)[:scanned]
#=> 2

## run_chores! batches via load_multi (batch_size smaller than population)
HousekeepingBulkMulti.run_chores!(chore_name: :strip_name, batch_size: 1)[:scanned]
#=> 4

## run_chores! isolates per-record errors and continues
class HousekeepingBulkError < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id
  field :payload

  chore(:explode) { |o| raise 'kaboom' if o.payload == 'bad'; o.payload && true }
end
@be1 = HousekeepingBulkError.new(id: 'be1', payload: 'good'); @be1.save
@be2 = HousekeepingBulkError.new(id: 'be2', payload: 'bad');  @be2.save
@be3 = HousekeepingBulkError.new(id: 'be3', payload: 'good'); @be3.save
@err_result = HousekeepingBulkError.run_chores!
@err_result[:chores][:explode]
#=> {modified: 2, errors: 1}

## run_chores! still reports scanned count including failed records
@err_result[:scanned]
#=> 3

## run_chores! raises when no chores are registered
class HousekeepingBulkEmpty < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id
end
begin
  HousekeepingBulkEmpty.run_chores!
rescue ArgumentError => e
  e.message
end
#=> "#{HousekeepingBulkEmpty.name} has no chores registered"

## run_chores! raises on unknown chore_name
begin
  HousekeepingBulk.run_chores!(chore_name: :nonexistent)
rescue ArgumentError => e
  e.message
end
#=> "unknown chore :nonexistent"

## run_chores! returns scanned: 0 when instances collection is empty
@bulk1.destroy!; @bulk2.destroy!; @bulk3.destroy!
HousekeepingBulk.run_chores!.slice(:scanned, :chores)
#=> {scanned: 0, chores: {uppercase_code: {modified: 0, errors: 0}}}

## Cleanup
@org.destroy! if @org.exists?
@org2.destroy! if @org2.exists?
@org3.destroy! if @org3.exists?
@noop.destroy! if @noop.exists?
@raiser.destroy! if @raiser.exists?
@rep.destroy! if @rep.exists?
@child.destroy! if @child.exists?
@override.destroy! if @override.exists?
@m1.destroy! if @m1.exists?
@m2.destroy! if @m2.exists?
@m3.destroy! if @m3.exists?
@m4.destroy! if @m4.exists?
@be1.destroy! if @be1.exists?
@be2.destroy! if @be2.exists?
@be3.destroy! if @be3.exists?
true
#=> true
