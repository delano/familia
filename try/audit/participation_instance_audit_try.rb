# try/audit/participation_instance_audit_try.rb
#
# Tests audit and repair for instance-level participation collections.
# When Domain participates_in Customer :domains, each Customer instance
# has its own sorted set of domain identifiers. If a Domain is deleted
# but its identifier lingers in customer.domains, audit should find it
# and repair should remove it from the actual collection.
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class AuditCustomer < Familia::Horreum
  feature :relationships

  identifier_field :cid
  field :cid
  field :name

  sorted_set :domains
end

class AuditDomain < Familia::Horreum
  feature :relationships

  identifier_field :did
  field :did
  field :display_name
  field :created_at

  participates_in AuditCustomer, :domains, score: :created_at
end

# Clean up
begin
  existing = Familia.dbclient.keys('audit_customer:*')
  existing += Familia.dbclient.keys('audit_domain:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditCustomer.instances.clear
AuditDomain.instances.clear

## Setup: create a customer and three domains
@customer = AuditCustomer.new(cid: 'ac-1', name: 'Acme')
@customer.save
@d1 = AuditDomain.new(did: 'ad-1', display_name: 'example.com', created_at: Familia.now.to_f)
@d1.save
@d2 = AuditDomain.new(did: 'ad-2', display_name: 'test.com', created_at: Familia.now.to_f + 1)
@d2.save
@d3 = AuditDomain.new(did: 'ad-3', display_name: 'demo.com', created_at: Familia.now.to_f + 2)
@d3.save
@customer.add_domains_instance(@d1)
@customer.add_domains_instance(@d2)
@customer.add_domains_instance(@d3)
@customer.domains.size
#=> 3

## AuditDomain has participation_relationships
AuditDomain.participation_relationships.size
#=> 1

## audit_participations detects no stale when all objects exist
@audit = AuditDomain.audit_participations
@audit.first[:stale_members].size
#=> 0

## Delete one domain key, leaving it in customer.domains
Familia.dbclient.del(@d1.dbkey)
AuditDomain.exists?('ad-1')
#=> false

## Stale member is still in the raw collection
@customer.domains.membersraw.include?('ad-1')
#=> true

## audit_participations finds the stale member
@audit = AuditDomain.audit_participations
@stale = @audit.first[:stale_members]
@stale.size
#=> 1

## Stale entry includes the correct identifier
@stale.first[:identifier]
#=> "ad-1"

## Stale entry includes the collection_key for the customer's domains
@stale.first[:collection_key]
#=> @customer.domains.dbkey

## Stale entry includes the collection_name
@stale.first[:collection_name]
#=> :domains

## Stale entry includes the reason
@stale.first[:reason]
#=> :object_missing

## repair_participations! removes stale member from actual collection
@result = AuditDomain.repair_participations!
@result[:stale_removed]
#=> 1

## After repair, stale domain is gone from customer.domains
@customer.domains.membersraw.include?('ad-1')
#=> false

## After repair, valid domains remain
@customer.domains.size
#=> 2

## After repair, valid domain ad-2 is still in collection
@customer.domains.membersraw.include?('ad-2')
#=> true

## After repair, valid domain ad-3 is still in collection
@customer.domains.membersraw.include?('ad-3')
#=> true

## Instances timeline was NOT modified by participation repair
AuditDomain.instances.size
#=> 3

## Multiple customers: create a second customer with overlapping domain
@customer2 = AuditCustomer.new(cid: 'ac-2', name: 'Beta Corp')
@customer2.save
@customer2.add_domains_instance(@d2)
@customer2.add_domains_instance(@d3)
@customer2.domains.size
#=> 2

## Delete d2, now stale in both customer collections
Familia.dbclient.del(@d2.dbkey)
@audit = AuditDomain.audit_participations
@total_stale = @audit.sum { |r| r[:stale_members].size }
@total_stale
#=> 2

## repair removes from both customer collections
@result = AuditDomain.repair_participations!
@result[:stale_removed]
#=> 2

## customer1 no longer has d2
@customer.domains.membersraw.include?('ad-2')
#=> false

## customer2 no longer has d2
@customer2.domains.membersraw.include?('ad-2')
#=> false

## customer1 still has d3
@customer.domains.membersraw.include?('ad-3')
#=> true

## customer2 still has d3
@customer2.domains.membersraw.include?('ad-3')
#=> true

## Clean state after repair
@audit = AuditDomain.audit_participations
@total_stale = @audit.sum { |r| r[:stale_members].size }
@total_stale
#=> 0

## sample_size on instance participations: setup multiple stale entries
@d4 = AuditDomain.new(did: 'ad-4', display_name: 'four.com', created_at: Familia.now.to_f + 3)
@d4.save
@d5 = AuditDomain.new(did: 'ad-5', display_name: 'five.com', created_at: Familia.now.to_f + 4)
@d5.save
@d6 = AuditDomain.new(did: 'ad-6', display_name: 'six.com', created_at: Familia.now.to_f + 5)
@d6.save
@customer.add_domains_instance(@d4)
@customer.add_domains_instance(@d5)
@customer.add_domains_instance(@d6)
Familia.dbclient.del(@d4.dbkey)
Familia.dbclient.del(@d5.dbkey)
Familia.dbclient.del(@d6.dbkey)
@full_audit = AuditDomain.audit_participations
@full_stale = @full_audit.sum { |r| r[:stale_members].size }
@full_stale
#=> 3

## sample_size: 1 limits members checked per collection
@sampled = AuditDomain.audit_participations(sample_size: 1)
@sampled_stale = @sampled.sum { |r| r[:stale_members].size }
@sampled_stale <= 1
#=> true

## sample_size larger than collection returns all stale members
@large_sampled = AuditDomain.audit_participations(sample_size: 100)
@large_stale = @large_sampled.sum { |r| r[:stale_members].size }
@large_stale
#=> 3

# Teardown
begin
  existing = Familia.dbclient.keys('audit_customer:*')
  existing += Familia.dbclient.keys('audit_domain:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditCustomer.instances.clear
AuditDomain.instances.clear
