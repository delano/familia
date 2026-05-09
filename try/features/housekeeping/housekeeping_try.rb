# try/features/housekeeping/housekeeping_try.rb
#
# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Test the housekeeping feature: a tiny DSL for declaring named chores
# (cleanup blocks) and running them against a single instance.

class HousekeepingOrg < Familia::Horreum
  feature :housekeeping

  identifier_field :id
  field :id
  field :planid
  field :email

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

  chore :downcase_email do |org|
    next unless org.email
    canonical = org.email.downcase
    if canonical != org.email
      org.email = canonical
      org.save
      true
    end
  end
end

class NoChoreOrg < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id
end

@suffix = "#{Process.pid}_#{Familia.now.to_i}"

# --- API surface ------------------------------------------------------------

## Class responds to chore DSL
HousekeepingOrg.respond_to?(:chore)
#=> true

## Class responds to chores reader
HousekeepingOrg.respond_to?(:chores)
#=> true

## Instances respond to tidy!
HousekeepingOrg.new(id: "api_#{@suffix}").respond_to?(:tidy!)
#=> true

## Registered chores are visible by name
HousekeepingOrg.chores.keys.sort
#=> [:downcase_email, :standardize_planid]

## chores reader returns a duped hash so callers can't corrupt the registry
mutated = HousekeepingOrg.chores
mutated.delete(:standardize_planid)
HousekeepingOrg.chores.keys.sort
#=> [:downcase_email, :standardize_planid]

## chore requires a block
begin
  HousekeepingOrg.chore(:no_block)
rescue ArgumentError => e
  e.message
end
#=> "chore requires a block"

## tidy! with unknown name raises Familia::Problem
begin
  HousekeepingOrg.new(id: "raise_#{@suffix}").tidy!(:not_a_real_chore)
rescue Familia::Problem => e
  e.message.include?('Unknown chore')
end
#=> true

# --- Functional behaviour ---------------------------------------------------

## tidy! with no args runs every chore and returns a hash keyed by chore name
@org = HousekeepingOrg.new(
  id: "func_#{@suffix}",
  planid: 'Pro',
  email: 'A@Example.com',
)
@org.save
@result = @org.tidy!
@result.keys.sort
#=> [:downcase_email, :standardize_planid]

## Both chores returned truthy and the record was modified in place
[@result[:standardize_planid], @result[:downcase_email]]
#=> [true, true]

## planid was canonicalized
@org.planid
#=> "professional"

## email was downcased
@org.email
#=> "a@example.com"

## Persisted state matches the in-memory state
reloaded = HousekeepingOrg.find_by_id(@org.id)
[reloaded.planid, reloaded.email]
#=> ["professional", "a@example.com"]

## Re-running tidy! is a no-op (idempotent): blocks return nil
rerun = @org.tidy!
[rerun[:standardize_planid], rerun[:downcase_email]]
#=> [nil, nil]

## tidy!(name) runs only the named chore
@org2 = HousekeepingOrg.new(
  id: "func2_#{@suffix}",
  planid: 'free',
  email: 'B@Example.com',
)
@org2.save
@org2.tidy!(:standardize_planid).keys
#=> [:standardize_planid]

## After targeted run only planid changed; email is still mixed-case
[@org2.planid, @org2.email]
#=> ["free", "B@Example.com"]

## A class with the feature but no chores returns an empty hash from tidy!
NoChoreOrg.new(id: "empty_#{@suffix}").tidy!
#=> {}

## Block return value is preserved verbatim (chore can return any value)
class CustomReturnOrg < Familia::Horreum
  feature :housekeeping
  identifier_field :id
  field :id

  chore :report do |_org|
    { changed: %i[a b], skipped: 1 }
  end
end
CustomReturnOrg.new(id: "ret_#{@suffix}").tidy!(:report)[:report]
#=> {:changed=>[:a, :b], :skipped=>1}

# Cleanup
@org.destroy! if @org
@org2.destroy! if @org2
