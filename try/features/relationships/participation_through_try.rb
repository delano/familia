# try/features/relationships/participation_through_try.rb
#
# frozen_string_literal: true

# Test through model support for participates_in relationships

require_relative '../../support/helpers/test_helpers'

# Define through model FIRST so it can be resolved
class ::ThroughTestMembership < Familia::Horreum
  feature :object_identifier
  feature :relationships
  identifier_field :objid
  field :through_test_customer_objid
  field :through_test_domain_objid
  field :role
  field :updated_at
end

class ::ThroughTestCustomer < Familia::Horreum
  feature :object_identifier
  feature :relationships
  identifier_field :custid
  field :custid
  field :name
end

class ::ThroughTestDomain < Familia::Horreum
  feature :object_identifier
  feature :relationships
  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at
  participates_in ThroughTestCustomer, :domains, score: :created_at, through: :ThroughTestMembership
end

# Define backward compat classes in setup
class ::BackwardCompatCustomer < Familia::Horreum
  feature :relationships
  identifier_field :custid
  field :custid
end

class ::BackwardCompatDomain < Familia::Horreum
  feature :relationships
  identifier_field :domain_id
  field :domain_id
  field :created_at
  participates_in BackwardCompatCustomer, :domains, score: :created_at
end

# Setup instance variables
@customer = ThroughTestCustomer.new(custid: 'cust_through_123', name: 'Through Test Customer')
@domain = ThroughTestDomain.new(domain_id: 'dom_through_456', display_domain: 'through-test.com', created_at: Familia.now.to_i)
@customer.save
@domain.save

@compat_customer = BackwardCompatCustomer.new(custid: 'compat_cust')
@compat_domain = BackwardCompatDomain.new(domain_id: 'compat_dom', created_at: Familia.now.to_i)
@compat_customer.save
@compat_domain.save

## ParticipationRelationship supports through parameter
Familia::Features::Relationships::ParticipationRelationship.members.include?(:through)
#=> true

## participates_in creates relationship with through parameter
@rel = ThroughTestDomain.participation_relationships.first
@rel.through
#=> :ThroughTestMembership

## Through class must have object_identifier feature
begin
  class ::InvalidThroughModel < Familia::Horreum
    feature :relationships
  end
  class ::BadDomain < Familia::Horreum
    feature :relationships
    field :name
    participates_in ThroughTestCustomer, :bad_domains, through: :InvalidThroughModel
  end
  false
rescue ArgumentError => e
  e.message.include?('must use `feature :object_identifier`')
end
#=> true

## Adding domain creates through model automatically
@membership1 = @customer.add_domains_instance(@domain)
@through_key = "through_test_customer:#{@customer.objid}:through_test_domain:#{@domain.objid}:through_test_membership"
@loaded_membership = ThroughTestMembership.load(@through_key)
@loaded_membership&.exists?
#=> true

## Through model receives through_attrs on add
@customer.remove_domains_instance(@domain)
@membership2 = @customer.add_domains_instance(@domain, through_attrs: { role: 'admin' })
@loaded_with_role = ThroughTestMembership.load(@through_key)
@loaded_with_role.role
#=> 'admin'

## add_domains_instance returns through model when using :through
@membership2.class.name
#=> "ThroughTestMembership"

## Returned through model can be chained
@membership2.respond_to?(:role)
#=> true

## Returned through model has role attribute set
@membership2.role
#=> 'admin'

## Removing domain destroys through model
@customer.remove_domains_instance(@domain)
@removed_check = ThroughTestMembership.load(@through_key)
@removed_check.nil? || !@removed_check.exists?
#=> true

## Adding twice updates existing, doesn't duplicate
@membership_v1 = @customer.add_domains_instance(@domain, through_attrs: { role: 'viewer' })
@check_v1 = ThroughTestMembership.load(@through_key)
@check_v1.role
#=> 'viewer'

## Second add updates the same through model
@membership_v2 = @customer.add_domains_instance(@domain, through_attrs: { role: 'editor' })
@check_v2 = ThroughTestMembership.load(@through_key)
@check_v2.role
#=> 'editor'

## Only one through model exists (same objid)
@check_v1.objid == @check_v2.objid
#=> true

## Models without :through work as before
@compat_result = @compat_customer.add_domains_instance(@compat_domain)
@compat_domain.in_backward_compat_customer_domains?(@compat_customer)
#=> true

## No through model created for backward compat
@compat_rel = BackwardCompatDomain.participation_relationships.first
@compat_rel.through.nil?
#=> true

## Backward compat returns self not through model
@compat_result.class.name
#=> "BackwardCompatCustomer"

## Through model sets updated_at on create
@customer.remove_domains_instance(@domain)
@membership_with_ts = @customer.add_domains_instance(@domain, through_attrs: { role: 'owner' })
@ts_check = ThroughTestMembership.load(@through_key)
@ts_check.updated_at.is_a?(Float)
#=> true

## updated_at is current
(Familia.now.to_f - @ts_check.updated_at) < 2.0
#=> true

## Through model updates updated_at on attribute change
@old_ts = @ts_check.updated_at
sleep 0.1
@membership_updated = @customer.add_domains_instance(@domain, through_attrs: { role: 'admin' })
@new_ts_check = ThroughTestMembership.load(@through_key)
@new_ts_check.updated_at > @old_ts
#=> true

# Cleanup
[@customer, @domain, @compat_customer, @compat_domain].each do |obj|
  obj.destroy! if obj&.respond_to?(:destroy!) && obj.exists?
end
