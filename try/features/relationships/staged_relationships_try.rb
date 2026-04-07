# try/features/relationships/staged_relationships_try.rb
#
# Tests for staged (deferred) relationships - invitation workflows where through
# models exist before participants do.
#
# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'

# Define test models for staged relationship testing
# All models need feature :object_identifier for objid method used in through model operations
class StagedTestOrganization < Familia::Horreum
  feature :object_identifier
  feature :relationships
  identifier_field :org_id
  field :org_id
  field :name
end

class StagedTestMembership < Familia::Horreum
  feature :object_identifier
  feature :relationships
  # Use objid as identifier (supports both UUID and composite key patterns)
  identifier_field :objid
  # Explicit prefix for predictable composite key format
  prefix :stagedtestmembership
  field :staged_test_organization_objid
  field :staged_test_customer_objid
  field :email
  field :role
  field :status
  field :token
  field :created_at
  field :updated_at
end

class StagedTestCustomer < Familia::Horreum
  feature :object_identifier
  feature :relationships
  identifier_field :custid
  field :custid
  field :email
  field :joined

  participates_in StagedTestOrganization, :members,
    score: :joined,
    through: StagedTestMembership,
    staged: :pending_members
end

# Test model without through (for validation testing)
class NonStagedTestOrganization < Familia::Horreum
  feature :relationships
  identifier_field :org_id
  field :org_id
end

@org = StagedTestOrganization.new(org_id: 'staged_test_org', name: 'Test Organization')
@org.save

## Configuration validation: staged requires through
# This test verifies the validation error message
begin
  eval <<~RUBY
    class InvalidStagedRelationship < Familia::Horreum
      feature :relationships
      identifier_field :custid
      field :custid
      participates_in NonStagedTestOrganization, :members, staged: :pending_members
    end
  RUBY
  false # Should have raised
rescue ArgumentError => e
  e.message.include?('staged: requires through: option')
end
#=> true

## Organization has both active and staging collections
@org.respond_to?(:members)
#=> true

## Organization has staging set
@org.respond_to?(:pending_members)
#=> true

## Organization has stage method
@org.respond_to?(:stage_members_instance)
#=> true

## Organization has activate method
@org.respond_to?(:activate_members_instance)
#=> true

## Organization has unstage method
@org.respond_to?(:unstage_members_instance)
#=> true

## Stage operation creates through model
@staged_membership = @org.stage_members_instance(
  through_attrs: {
    email: 'invite@example.com',
    role: 'member',
    status: 'pending',
    token: 'test_token_123'
  }
)
@staged_membership.is_a?(StagedTestMembership)
#=> true

## Staged model has UUID-style objid (not composite key)
# Composite keys contain colons with class prefixes, UUIDs don't follow that pattern
!@staged_membership.objid.include?('stagedtestorganization')
#=> true

## Staged model has target objid set
@staged_membership.staged_test_organization_objid == @org.objid
#=> true

## Staged model has nil customer objid (participant doesn't exist yet)
@staged_membership.staged_test_customer_objid.nil?
#=> true

## Staged model has custom attributes
@staged_membership.email == 'invite@example.com'
#=> true

## Staged model has role
@staged_membership.role == 'member'
#=> true

## Staged model has status
@staged_membership.status == 'pending'
#=> true

## Staged model has token
@staged_membership.token == 'test_token_123'
#=> true

## Staging set contains the through model objid
@org.pending_members.member?(@staged_membership.objid)
#=> true

## Staging set size is 1
@org.pending_members.size == 1
#=> true

## Active set is still empty
@org.members.size == 0
#=> true

## Now create a customer (simulating user signup)
@customer = StagedTestCustomer.new(
  custid: 'staged_test_customer',
  email: 'invite@example.com',
  joined: Familia.now.to_f
)
@customer.save
@customer.exists?
#=> true

## Activate the staged membership
@activated_membership = @org.activate_members_instance(
  @staged_membership,
  @customer,
  through_attrs: {
    email: @staged_membership.email,
    role: @staged_membership.role,
    status: 'active',
    token: nil
  }
)
@activated_membership.is_a?(StagedTestMembership)
#=> true

## Activated model has composite key (contains target config_name)
# Note: Composite keys use config_name (e.g., staged_test_organization) not prefix
@activated_membership.objid.include?('staged_test_organization')
#=> true

## Activated model has customer objid set
@activated_membership.staged_test_customer_objid == @customer.objid
#=> true

## Activated model has status updated
@activated_membership.status == 'active'
#=> true

## Activated model has token cleared
@activated_membership.token.nil?
#=> true

## Staged model was destroyed
!@staged_membership.exists?
#=> true

## Active set now contains the customer
# Note: Use the customer object (not identifier string) for member? check
# because Familia extracts the identifier from objects but JSON-encodes plain strings
@org.members.member?(@customer)
#=> true

## Active set size is 1
@org.members.size == 1
#=> true

## Staging set is now empty
@org.pending_members.size == 0
#=> true

## Customer's participations set is populated
@customer.participations.size == 1
#=> true

## Test unstage (revoke invitation)
@staged_membership2 = @org.stage_members_instance(
  through_attrs: {
    email: 'revoke@example.com',
    role: 'viewer',
    status: 'pending',
    token: 'revoke_token'
  }
)
@staged_membership2.exists?
#=> true

## Staging set has the new membership
@org.pending_members.member?(@staged_membership2.objid)
#=> true

## Unstage removes from staging set and destroys model
@org.unstage_members_instance(@staged_membership2)
@org.pending_members.member?(@staged_membership2.objid)
#=> false

## Unstaged model is destroyed
!@staged_membership2.exists?
#=> true

## Staging set is empty again
@org.pending_members.size == 0
#=> true

## ParticipationRelationship has staged? method
@rel = StagedTestCustomer.participation_relationships.first
@rel.staged?
#=> true

## ParticipationRelationship has staging_collection_name method
@rel.staging_collection_name == :pending_members
#=> true

## Non-staged relationships don't break - setup models
# Create a simple non-staged relationship to verify backwards compatibility
class NonStagedCustomer < Familia::Horreum
  feature :object_identifier  # Required for objid used in through model composite keys
  feature :relationships
  identifier_field :custid
  field :custid
end

class SimpleMembership < Familia::Horreum
  feature :object_identifier
  identifier_field :objid
  field :non_staged_org_objid
  field :non_staged_domain_objid
end

class NonStagedOrg < Familia::Horreum
  feature :object_identifier  # Required for objid used in through model composite keys
  feature :relationships
  identifier_field :org_id
  field :org_id
end

class NonStagedDomain < Familia::Horreum
  feature :object_identifier  # Required for objid used in through model composite keys
  feature :relationships
  identifier_field :domain_id
  field :domain_id
  field :created_at

  participates_in NonStagedOrg, :domains, score: :created_at, through: SimpleMembership
end
NonStagedDomain.ancestors.include?(Familia::Horreum)
#=> true

## Non-staged organization and domain can be created
@ns_org = NonStagedOrg.new(org_id: 'non_staged_org')
@ns_org.save
@ns_domain = NonStagedDomain.new(domain_id: 'test_domain', created_at: Familia.now.to_f)
@ns_domain.save
@ns_org.exists? && @ns_domain.exists?
#=> true

## Non-staged add still works
@ns_membership = @ns_org.add_domains_instance(@ns_domain)
@ns_membership.is_a?(SimpleMembership)
#=> true

## Non-staged organization has no staging methods
!@ns_org.respond_to?(:stage_domains_instance)
#=> true

## Non-staged organization has no activate method
!@ns_org.respond_to?(:activate_domains_instance)
#=> true

## Non-staged organization has no unstage method
!@ns_org.respond_to?(:unstage_domains_instance)
#=> true

# Edge Case Tests

## Double activation: setup - create a new staged membership
@double_staged = @org.stage_members_instance(
  through_attrs: {
    email: 'double@example.com',
    role: 'member',
    status: 'pending',
    token: 'double_token'
  }
)
@double_staged.exists?
#=> true

## Double activation: first activation succeeds
@double_customer = StagedTestCustomer.new(
  custid: 'double_test_customer',
  email: 'double@example.com',
  joined: Familia.now.to_f
)
@double_customer.save
@double_activated = @org.activate_members_instance(
  @double_staged,
  @double_customer,
  through_attrs: {
    email: @double_staged.email,
    role: @double_staged.role,
    status: 'active',
    token: nil
  }
)
@double_activated.is_a?(StagedTestMembership)
#=> true

## Double activation: staged model no longer exists after first activation
!@double_staged.exists?
#=> true

## Double activation: second activation raises error (requires exists? validation)
# After the first activation, the staged model was destroyed.
# Attempting to activate it again should raise an error because the staged model
# no longer exists in Redis.
# NOTE: This test requires validation that checks staged_model.exists? before activation.
# Until that validation is added, this test will fail (the code will silently proceed).
begin
  @org.activate_members_instance(
    @double_staged,
    @double_customer,
    through_attrs: { status: 'active' }
  )
  false # Should have raised
rescue ArgumentError => e
  e.message.include?('does not exist') || e.message.include?('staged model')
end
#=> true

## Cross-target activation: setup - create a second organization
@org2 = StagedTestOrganization.new(org_id: 'staged_test_org2', name: 'Second Organization')
@org2.save
@org2.exists?
#=> true

## Cross-target activation: stage membership on first org
@cross_staged = @org.stage_members_instance(
  through_attrs: {
    email: 'cross@example.com',
    role: 'admin',
    status: 'pending',
    token: 'cross_token'
  }
)
@cross_staged.staged_test_organization_objid == @org.objid
#=> true

## Cross-target activation: attempt to activate on different org raises error
@cross_customer = StagedTestCustomer.new(
  custid: 'cross_test_customer',
  email: 'cross@example.com',
  joined: Familia.now.to_f
)
@cross_customer.save
begin
  @org2.activate_members_instance(
    @cross_staged,
    @cross_customer,
    through_attrs: { status: 'active' }
  )
  false # Should have raised
rescue ArgumentError => e
  e.message.include?('different target')
end
#=> true

## Cross-target activation: cleanup staged model
@org.unstage_members_instance(@cross_staged)
!@cross_staged.exists?
#=> true

## Unstage on already-destroyed model: setup - create and manually destroy
@ghost_staged = @org.stage_members_instance(
  through_attrs: {
    email: 'ghost@example.com',
    role: 'viewer',
    status: 'pending',
    token: 'ghost_token'
  }
)
@ghost_objid = @ghost_staged.objid
@org.pending_members.member?(@ghost_objid)
#=> true

## Unstage on already-destroyed model: manually destroy the model (simulate TTL expiration)
@ghost_staged.destroy!
!@ghost_staged.exists?
#=> true

## Unstage on already-destroyed model: unstage handles gracefully (returns false)
# The model no longer exists, but we should be able to call unstage without error
result = @org.unstage_members_instance(@ghost_staged)
# The method should return false since the model doesn't exist
result == false
#=> true

## Ghost entry cleanup via load_staged: setup - create a staged model
@load_staged_model = @org.stage_members_instance(
  through_attrs: {
    email: 'load_staged@example.com',
    role: 'member',
    status: 'pending',
    token: 'load_token'
  }
)
@load_staged_objid = @load_staged_model.objid
@load_staged_model.exists?
#=> true

## Ghost entry cleanup via load_staged: valid model returns the model
loaded = Familia::Features::Relationships::Participation::StagedOperations.load_staged(
  through_class: StagedTestMembership,
  staged_objid: @load_staged_objid,
  staging_collection: @org.pending_members
)
loaded.objid == @load_staged_objid
#=> true

## Ghost entry cleanup via load_staged: setup ghost entry
# Manually destroy the model but leave entry in staging set
@load_staged_model.destroy!
!@load_staged_model.exists?
#=> true

## Ghost entry cleanup via load_staged: staging set still has the entry (ghost)
@org.pending_members.member?(@load_staged_objid)
#=> true

## Ghost entry cleanup via load_staged: load_staged returns nil for ghost
loaded_ghost = Familia::Features::Relationships::Participation::StagedOperations.load_staged(
  through_class: StagedTestMembership,
  staged_objid: @load_staged_objid,
  staging_collection: @org.pending_members
)
loaded_ghost.nil?
#=> true

## Ghost entry cleanup via load_staged: ghost entry was cleaned up
!@org.pending_members.member?(@load_staged_objid)
#=> true

## Clean up test data
[@org, @org2, @customer, @activated_membership, @double_customer, @double_activated,
 @cross_customer, @ns_org, @ns_domain, @ns_membership].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj&.exists?
end
true
#=> true
