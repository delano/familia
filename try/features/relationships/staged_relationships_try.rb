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

# Bulk Staging Operations

## Bulk stage: method exists on target class
@org.respond_to?(:stage_members)
#=> true

## Bulk unstage: method exists on target class
@org.respond_to?(:unstage_members)
#=> true

## Bulk stage: empty list returns empty array
@org.stage_members([]).empty?
#=> true

## Bulk stage: create multiple invitations
@bulk_staged = @org.stage_members([
  { email: 'bulk1@example.com', role: 'viewer', status: 'pending', token: 'bulk_token_1' },
  { email: 'bulk2@example.com', role: 'admin', status: 'pending', token: 'bulk_token_2' },
  { email: 'bulk3@example.com', role: 'member', status: 'pending', token: 'bulk_token_3' }
])
@bulk_staged.size == 3
#=> true

## Bulk stage: all models are StagedTestMembership instances
@bulk_staged.all? { |m| m.is_a?(StagedTestMembership) }
#=> true

## Bulk stage: all models have UUID keys (not composite)
@bulk_staged.none? { |m| m.objid.include?('staged_test_organization') }
#=> true

## Bulk stage: all models added to staging collection
@bulk_staged.all? { |m| @org.pending_members.member?(m.objid) }
#=> true

## Bulk stage: all models have correct target FK
@bulk_staged.all? { |m| m.staged_test_organization_objid == @org.objid }
#=> true

## Bulk stage: all models preserve their unique attributes
[@bulk_staged[0].email == 'bulk1@example.com',
 @bulk_staged[1].email == 'bulk2@example.com',
 @bulk_staged[2].email == 'bulk3@example.com'].all?
#=> true

## Bulk stage: models have different roles as specified
[@bulk_staged[0].role == 'viewer',
 @bulk_staged[1].role == 'admin',
 @bulk_staged[2].role == 'member'].all?
#=> true

## Bulk unstage: empty list returns 0
@org.unstage_members([]) == 0
#=> true

## Bulk unstage: with model objects
@bulk_unstage_models = @org.stage_members([
  { email: 'unstage1@example.com', role: 'viewer', status: 'pending', token: 'unstage_1' },
  { email: 'unstage2@example.com', role: 'viewer', status: 'pending', token: 'unstage_2' }
])
@bulk_unstage_models.size == 2
#=> true

## Bulk unstage: unstage with model objects returns correct count
count = @org.unstage_members(@bulk_unstage_models)
count == 2
#=> true

## Bulk unstage: models removed from staging collection
@bulk_unstage_models.none? { |m| @org.pending_members.member?(m.objid) }
#=> true

## Bulk unstage: models destroyed
@bulk_unstage_models.none? { |m| m.exists? }
#=> true

## Bulk unstage with objids: setup - create new models
@bulk_objid_models = @org.stage_members([
  { email: 'objid1@example.com', role: 'viewer', status: 'pending', token: 'objid_1' },
  { email: 'objid2@example.com', role: 'viewer', status: 'pending', token: 'objid_2' }
])
@bulk_objids = @bulk_objid_models.map(&:objid)
@bulk_objids.size == 2
#=> true

## Bulk unstage with objids: unstage using objid strings
count = @org.unstage_members(@bulk_objids)
count == 2
#=> true

## Bulk unstage with objids: models destroyed via objid lookup
@bulk_objid_models.none? { |m| m.exists? }
#=> true

## Bulk unstage with ghost entries: setup - create and manually destroy some
@ghost_bulk_models = @org.stage_members([
  { email: 'ghost_bulk1@example.com', role: 'viewer', status: 'pending', token: 'ghost_bulk_1' },
  { email: 'ghost_bulk2@example.com', role: 'viewer', status: 'pending', token: 'ghost_bulk_2' }
])
# Manually destroy first model to create ghost entry
@ghost_bulk_models[0].destroy!
!@ghost_bulk_models[0].exists?
#=> true

## Bulk unstage with ghost entries: second model still exists
@ghost_bulk_models[1].exists?
#=> true

## Bulk unstage with ghost entries: returns count of actually destroyed (1, not 2)
count = @org.unstage_members(@ghost_bulk_models)
count == 1
#=> true

## Bulk unstage with ghost entries: all removed from staging collection
@ghost_bulk_models.none? { |m| @org.pending_members.member?(m.objid) }
#=> true

## Bulk stage cleanup: unstage remaining bulk_staged models
@org.unstage_members(@bulk_staged)
@bulk_staged.none? { |m| @org.pending_members.member?(m.objid) }
#=> true

# Additional Edge Case Tests

## Mixed valid/invalid bulk unstage: setup - create models and one non-existent objid
@mixed_unstage_models = @org.stage_members([
  { email: 'mixed1@example.com', role: 'viewer', status: 'pending', token: 'mixed_1' },
  { email: 'mixed2@example.com', role: 'viewer', status: 'pending', token: 'mixed_2' }
])
@mixed_unstage_models.size == 2
#=> true

## Mixed valid/invalid bulk unstage: mix model, objid string, and fake objid
@mixed_items = [
  @mixed_unstage_models[0],
  @mixed_unstage_models[1].objid,
  'nonexistent_objid_12345'
]
@mixed_items.size == 3
#=> true

## Mixed valid/invalid bulk unstage: returns count of actually destroyed (2, not 3)
count = @org.unstage_members(@mixed_items)
count == 2
#=> true

## Mixed valid/invalid bulk unstage: real models are destroyed
@mixed_unstage_models.none? { |m| m.exists? }
#=> true

## Invalid attribute filtering: setup - stage with unknown attributes
@invalid_attr_model = @org.stage_members_instance(
  through_attrs: {
    email: 'valid@example.com',
    role: 'member',
    unknown_field: 'should_be_ignored',
    another_fake: 12345,
    status: 'pending'
  }
)
@invalid_attr_model.is_a?(StagedTestMembership)
#=> true

## Invalid attribute filtering: valid attributes are set
[@invalid_attr_model.email == 'valid@example.com',
 @invalid_attr_model.role == 'member',
 @invalid_attr_model.status == 'pending'].all?
#=> true

## Invalid attribute filtering: model does not respond to unknown fields
!@invalid_attr_model.respond_to?(:unknown_field) && !@invalid_attr_model.respond_to?(:another_fake)
#=> true

## Invalid attribute filtering: cleanup
@org.unstage_members_instance(@invalid_attr_model)
!@invalid_attr_model.exists?
#=> true

## Empty through_attrs activation: setup - stage a model
@empty_attrs_staged = @org.stage_members_instance(
  through_attrs: {
    email: 'empty_attrs@example.com',
    role: 'viewer',
    status: 'pending',
    token: 'empty_attrs_token'
  }
)
@empty_attrs_staged.exists?
#=> true

## Empty through_attrs activation: create participant
@empty_attrs_customer = StagedTestCustomer.new(
  custid: 'empty_attrs_customer',
  email: 'empty_attrs@example.com',
  joined: Familia.now.to_f
)
@empty_attrs_customer.save
@empty_attrs_customer.exists?
#=> true

## Empty through_attrs activation: activate with empty through_attrs hash
@empty_attrs_activated = @org.activate_members_instance(
  @empty_attrs_staged,
  @empty_attrs_customer,
  through_attrs: {}
)
@empty_attrs_activated.is_a?(StagedTestMembership)
#=> true

## Empty through_attrs activation: model has composite key
@empty_attrs_activated.objid.include?('staged_test_organization')
#=> true

## Empty through_attrs activation: staged model destroyed
!@empty_attrs_staged.exists?
#=> true

## Empty through_attrs activation: participant in active set
@org.members.member?(@empty_attrs_customer)
#=> true

## Re-activation of existing member: setup - customer is already a member from previous test
# @empty_attrs_customer is already in @org.members from the empty through_attrs activation test
@org.members.member?(@empty_attrs_customer)
#=> true

## Re-activation of existing member: stage a new invitation for same org
@reactivate_staged = @org.stage_members_instance(
  through_attrs: {
    email: 'empty_attrs@example.com',
    role: 'admin',
    status: 'pending',
    token: 'reactivate_token'
  }
)
@reactivate_staged.exists?
#=> true

## Re-activation of existing member: activate for existing member (should be idempotent)
@reactivate_activated = @org.activate_members_instance(
  @reactivate_staged,
  @empty_attrs_customer,
  through_attrs: {
    role: 'admin',
    status: 'upgraded'
  }
)
@reactivate_activated.is_a?(StagedTestMembership)
#=> true

## Re-activation of existing member: staged model destroyed
!@reactivate_staged.exists?
#=> true

## Re-activation of existing member: customer still in active set (idempotent)
@org.members.member?(@empty_attrs_customer)
#=> true

## Re-activation of existing member: through model has updated attributes
@reactivate_activated.role == 'admin' && @reactivate_activated.status == 'upgraded'
#=> true

## load_staged with nil staging_collection: setup - create and destroy a staged model
@nil_staging_model = @org.stage_members_instance(
  through_attrs: {
    email: 'nil_staging@example.com',
    role: 'viewer',
    status: 'pending',
    token: 'nil_staging_token'
  }
)
@nil_staging_objid = @nil_staging_model.objid
@nil_staging_model.exists?
#=> true

## load_staged with nil staging_collection: staging set has the entry
@org.pending_members.member?(@nil_staging_objid)
#=> true

## load_staged with nil staging_collection: manually destroy to create ghost
@nil_staging_model.destroy!
!@nil_staging_model.exists?
#=> true

## load_staged with nil staging_collection: call load_staged with nil staging_collection
loaded_nil = Familia::Features::Relationships::Participation::StagedOperations.load_staged(
  through_class: StagedTestMembership,
  staged_objid: @nil_staging_objid,
  staging_collection: nil
)
loaded_nil.nil?
#=> true

## load_staged with nil staging_collection: ghost entry remains (no cleanup without collection)
@org.pending_members.member?(@nil_staging_objid)
#=> true

## load_staged with nil staging_collection: cleanup ghost entry manually
@org.pending_members.remove(@nil_staging_objid)
!@org.pending_members.member?(@nil_staging_objid)
#=> true

# Return Type Consistency Tests
#
# API design note: Single-item operations (unstage_members_instance) return
# boolean for success/failure semantics, while bulk operations (unstage_members)
# return Integer count for progress feedback. This is intentional:
# - Boolean: "Did this specific unstage succeed?" (yes/no)
# - Integer: "How many of these N items were actually unstaged?" (feedback)

## Return type: unstage_members_instance returns true when model destroyed
@return_type_staged = @org.stage_members_instance(
  through_attrs: {
    email: 'return_type@example.com',
    role: 'viewer',
    status: 'pending',
    token: 'return_type_token'
  }
)
@return_type_staged.exists?
#=> true

## Return type: unstage_members_instance returns true on successful destroy
result = @org.unstage_members_instance(@return_type_staged)
result == true
#=> true

## Return type: unstage_members_instance returns false when model already destroyed (ghost)
# Create a new staged model
@ghost_return_staged = @org.stage_members_instance(
  through_attrs: {
    email: 'ghost_return@example.com',
    role: 'viewer',
    status: 'pending',
    token: 'ghost_return_token'
  }
)
# Manually destroy to simulate TTL expiration or external deletion
@ghost_return_staged.destroy!
!@ghost_return_staged.exists?
#=> true

## Return type: unstage_members_instance returns false for ghost (model doesn't exist)
result = @org.unstage_members_instance(@ghost_return_staged)
result == false
#=> true

## Return type: unstage_members returns Integer count
@count_staged = @org.stage_members([
  { email: 'count1@example.com', role: 'viewer', status: 'pending', token: 'count_1' },
  { email: 'count2@example.com', role: 'viewer', status: 'pending', token: 'count_2' },
  { email: 'count3@example.com', role: 'viewer', status: 'pending', token: 'count_3' }
])
@count_staged.size == 3
#=> true

## Return type: unstage_members returns Integer (not boolean)
@unstage_count = @org.unstage_members(@count_staged)
@unstage_count.is_a?(Integer)
#=> true

## Return type: unstage_members returns correct count value
@unstage_count == 3
#=> true

## Clean up test data
[@org, @org2, @customer, @activated_membership, @double_customer, @double_activated,
 @cross_customer, @ns_org, @ns_domain, @ns_membership, @empty_attrs_customer,
 @empty_attrs_activated, @reactivate_activated].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj&.exists?
end
true
#=> true
