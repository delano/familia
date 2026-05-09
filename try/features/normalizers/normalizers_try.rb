# try/features/normalizers/normalizers_try.rb
#
# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Test the normalizers feature: a lightweight DSL for declaring data
# cleanup rules that iterate over every instance of a Horreum class.

class NormalizerOrg < Familia::Horreum
  feature :normalizers

  identifier_field :id
  field :id
  field :planid
  field :email

  normalizer :standardize_planid do |org|
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

  normalizer :downcase_email do |org|
    next unless org.email
    canonical = org.email.downcase
    if canonical != org.email
      org.email = canonical
      org.save
      true
    end
  end
end

class PlanOrg < Familia::Horreum
  feature :normalizers

  identifier_field :id
  field :id
  field :planid
  field :email

  normalizer :standardize_planid do |org|
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

  normalizer :downcase_email do |org|
    next unless org.email
    canonical = org.email.downcase
    if canonical != org.email
      org.email = canonical
      org.save
      true
    end
  end
end

class NormErrorOrg < Familia::Horreum
  feature :normalizers

  identifier_field :id
  field :id
  field :flag

  normalizer :buggy do |org|
    raise 'boom' if org.flag == 'explode'
    if org.flag == 'change'
      org.flag = 'changed'
      org.save
      true
    end
  end
end

class FloodOrg < Familia::Horreum
  feature :normalizers

  identifier_field :id
  field :id

  normalizer :always_fails do |_org|
    raise 'nope'
  end
end

class GhostOrg < Familia::Horreum
  feature :normalizers

  identifier_field :id
  field :id
  field :tag

  normalizer :touch do |org|
    if org.tag != 'touched'
      org.tag = 'touched'
      org.save
      true
    end
  end
end

class BatchOrg < Familia::Horreum
  feature :normalizers

  identifier_field :id
  field :id
  field :n

  # Idempotent: makes n odd; once odd, leave it alone.
  normalizer :make_odd do |org|
    next unless org.n.is_a?(Integer)
    if org.n.even?
      org.n += 1
      org.save
      true
    end
  end
end

# Wipe instances so per-test counts are deterministic
[NormalizerOrg, PlanOrg, NormErrorOrg, FloodOrg, GhostOrg, BatchOrg].each do |klass|
  klass.instances.clear
end

@suffix = "#{Process.pid}_#{Familia.now.to_i}"

# --- API surface ------------------------------------------------------------

## Class responds to normalizer DSL
NormalizerOrg.respond_to?(:normalizer)
#=> true

## Class responds to normalizers reader
NormalizerOrg.respond_to?(:normalizers)
#=> true

## Class responds to normalize!
NormalizerOrg.respond_to?(:normalize!)
#=> true

## Registered normalizers are visible by name
NormalizerOrg.normalizers.keys.sort
#=> [:downcase_email, :standardize_planid]

## normalizers reader returns a duped hash so callers can't corrupt the registry
mutated = NormalizerOrg.normalizers
mutated.delete(:standardize_planid)
NormalizerOrg.normalizers.keys.sort
#=> [:downcase_email, :standardize_planid]

## normalizer requires a block
begin
  NormalizerOrg.normalizer(:no_block)
rescue ArgumentError => e
  e.message
end
#=> "Normalizer requires a block"

## normalize! with unknown name raises Familia::Problem
begin
  NormalizerOrg.normalize!(:not_a_real_normalizer)
rescue Familia::Problem => e
  e.message.include?('Unknown normalizer')
end
#=> true

## Stats hash always includes scanned, modified, errors, error_messages
NormalizerOrg.normalize!(:standardize_planid)[:standardize_planid].keys.sort
#=> [:error_messages, :errors, :modified, :scanned]

# --- Functional run on a fresh dataset --------------------------------------

## Seed five plans and confirm count
@plan_seed = [
  ['pro',             'a@example.com'],
  ['Pro',             'b@Example.com'],
  ['professional_v1', 'c@example.com'],
  ['professional',    'd@example.com'],
  ['enterprise',      'e@example.com'],
].each_with_index.map do |(plan, email), idx|
  PlanOrg.new(id: "plan_#{@suffix}_#{idx}", planid: plan, email: email).tap(&:save)
end
PlanOrg.instances.element_count
#=> 5

## First run: scanned = 5, modified = 3 (pro, Pro, professional_v1)
@first_plan = PlanOrg.normalize!(:standardize_planid)[:standardize_planid]
[@first_plan[:scanned], @first_plan[:modified], @first_plan[:errors]]
#=> [5, 3, 0]

## error_messages defaults to empty array on success
@first_plan[:error_messages]
#=> []

## Second run is a no-op (idempotent): nothing left to modify
PlanOrg.normalize!(:standardize_planid)[:standardize_planid][:modified]
#=> 0

## "pro" was canonicalized
PlanOrg.find_by_id(@plan_seed[0].id).planid
#=> "professional"

## "Pro" was canonicalized
PlanOrg.find_by_id(@plan_seed[1].id).planid
#=> "professional"

## "professional_v1" was canonicalized
PlanOrg.find_by_id(@plan_seed[2].id).planid
#=> "professional"

## Already-canonical record left untouched
PlanOrg.find_by_id(@plan_seed[3].id).planid
#=> "professional"

## Unmatched planid is left as-is
PlanOrg.find_by_id(@plan_seed[4].id).planid
#=> "enterprise"

## normalize! with no name runs every registered normalizer
@all_stats = PlanOrg.normalize!
@all_stats.keys.sort
#=> [:downcase_email, :standardize_planid]

## downcase_email modified the one mixed-case email
@all_stats[:downcase_email][:modified]
#=> 1

## Confirm the email was actually downcased
PlanOrg.find_by_id(@plan_seed[1].id).email
#=> "b@example.com"

# --- Error isolation --------------------------------------------------------

## Errors are caught, counted, and one record still gets modified
NormErrorOrg.new(id: "err_#{@suffix}_0", flag: 'explode').save
NormErrorOrg.new(id: "err_#{@suffix}_1", flag: 'explode').save
NormErrorOrg.new(id: "err_#{@suffix}_2", flag: 'change').save
@err_stats = NormErrorOrg.normalize!(:buggy)[:buggy]
[@err_stats[:scanned], @err_stats[:modified], @err_stats[:errors]]
#=> [3, 1, 2]

## error_messages includes RuntimeError details for each failure
@err_stats[:error_messages].count { |m| m.include?('RuntimeError') && m.include?('boom') }
#=> 2

# --- error_messages cap -----------------------------------------------------

## error_messages caps at MAX_ERROR_MESSAGES (10) even with 20 failures
20.times { |i| FloodOrg.new(id: "flood_#{@suffix}_#{i}").save }
flood = FloodOrg.normalize!(:always_fails)[:always_fails]
[flood[:errors], flood[:error_messages].size]
#=> [20, 10]

# --- Ghost entries ----------------------------------------------------------

## Ghost entries (in instances but no hash key) are skipped silently
GhostOrg.new(id: "real_#{@suffix}", tag: 'fresh').save
GhostOrg.instances.add("ghost_#{@suffix}", Familia.now)
ghost = GhostOrg.normalize!(:touch)[:touch]
[ghost[:scanned], ghost[:modified], ghost[:errors]]
#=> [1, 1, 0]

# --- batch_size -------------------------------------------------------------

## batch_size controls slicing: 6 even values get bumped to odd
12.times { |i| BatchOrg.new(id: "batch_#{@suffix}_#{i}", n: i).save }
batch = BatchOrg.normalize!(:make_odd, batch_size: 5)[:make_odd]
[batch[:scanned], batch[:modified], batch[:errors]]
#=> [12, 6, 0]

## A second pass reaches the steady state (no further changes)
batch_again = BatchOrg.normalize!(:make_odd, batch_size: 5)[:make_odd]
[batch_again[:scanned], batch_again[:modified]]
#=> [12, 0]

# Cleanup
[NormalizerOrg, PlanOrg, NormErrorOrg, FloodOrg, GhostOrg, BatchOrg].each do |klass|
  klass.instances.clear
end
