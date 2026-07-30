# try/bug_fixes/relationships_rdoc_example_try.rb
#
# frozen_string_literal: true

# Pins the "Multi-collection operations" example in the Relationships rdoc.
# That block previously documented `update_multiple_presence` and
# `union_collections`, neither of which exists anywhere in lib/, and passed the
# second a `min_permission:` keyword. `min_permission` is a real name -- the
# positional parameter of the generated `<collection>_with_permission` -- but
# not a keyword of the method the example called. This file runs the
# replacement example verbatim so it cannot drift back into fiction.

require_relative '../support/helpers/test_helpers'

class ::RdocCustomer < Familia::Horreum
  feature :relationships
  identifier_field :custid
  field :custid
end

class ::RdocTeam < Familia::Horreum
  feature :relationships
  identifier_field :teamid
  field :teamid
end

class ::RdocDomain < Familia::Horreum
  feature :relationships
  identifier_field :domain_id
  field :domain_id

  participates_in ::RdocCustomer, :domains, type: :sorted_set
  participates_in ::RdocTeam, :domains, type: :sorted_set
end

@customer = ::RdocCustomer.new(custid: 'rdoc_cust_1')
@customer.save
@team = ::RdocTeam.new(teamid: 'rdoc_team_1')
@team.save
@domain = ::RdocDomain.new(domain_id: 'rdoc_domain_1')
@domain.save
@customer.domains.delete!
@team.domains.delete!
@domain.participations.delete!

## the rdoc's transaction block runs as written: several collections written
## through the connection layer, not a relationships-specific batch method
Familia.transaction do
  @customer.add_domains_instance(@domain, @domain.permission_encode(Familia.now, :read))
  @team.add_domains_instance(@domain, @domain.permission_encode(Familia.now, :read))
end
## (member? takes the object that was added, not its identifier string --
## both are serialized, and only the object serializes back to the stored form)
[@customer.domains.member?(@domain), @team.domains.member?(@domain)]
#=> [true, true]

## participating_ids_for_target answers the cross-collection question from the
## participant's reverse index
@domain.participating_ids_for_target(::RdocCustomer)
#=> ['rdoc_cust_1']

## and it accepts a collection-name filter
@domain.participating_ids_for_target(::RdocTeam, ['domains'])
#=> ['rdoc_team_1']

## a filter naming a collection this participant is not in returns nothing
@domain.participating_ids_for_target(::RdocTeam, ['nonexistent'])
#=> []

## participating_in_target? is the shallow membership check
[@domain.participating_in_target?(::RdocCustomer), @domain.participating_in_target?(::RdocTeam)]
#=> [true, true]

## the names the old rdoc advertised do not exist -- that was the defect
[@domain.respond_to?(:update_multiple_presence), ::RdocDomain.respond_to?(:union_collections)]
#=> [false, false]

@customer.domains.delete!
@team.domains.delete!
@domain.participations.delete!
@customer.destroy!
@team.destroy!
@domain.destroy!
