#!/usr/bin/env ruby
# examples/through_relationships.rb
#
# frozen_string_literal: true

# Through Relationships Example
# Demonstrates the :through option for participates_in, which creates
# intermediate join models with additional attributes (roles, metadata, etc.)

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'familia'

# Configure Familia for the example
# Use port 2525 (Familia test database) or set REDIS_URL
Familia.configure do |config|
  config.uri = ENV.fetch('REDIS_URL', 'redis://localhost:2525/')
end

puts '=== Familia Through Relationships Example ==='
puts
puts 'The :through option creates join models between participants and targets,'
puts 'similar to has_many :through in ActiveRecord but for Redis.'
puts

# ============================================================================
# MODEL DEFINITIONS
# ============================================================================

# The through model MUST use feature :object_identifier
# This enables deterministic key generation for the join record
class Membership < Familia::Horreum
  logical_database 15
  feature :object_identifier  # REQUIRED for through models
  feature :relationships

  identifier_field :objid

  # Foreign keys (auto-set by through operations)
  field :organization_objid
  field :user_objid

  # Additional attributes - this is why we use :through!
  field :role           # 'owner', 'admin', 'member'
  field :permissions    # JSON or comma-separated list
  field :invited_by     # Who invited this user
  field :invited_at     # When they were invited
  field :joined_at      # When they accepted
  field :updated_at     # Auto-set for cache invalidation
end

class Organization < Familia::Horreum
  logical_database 15
  feature :object_identifier
  feature :relationships

  identifier_field :objid  # Use objid as identifier (auto-generated)
  field :name
  field :plan
end

class User < Familia::Horreum
  logical_database 15
  feature :object_identifier
  feature :relationships

  identifier_field :objid  # Use objid as identifier (auto-generated)
  field :email
  field :name

  # Declare participation WITH a through model
  # This creates Membership records when adding users to organizations
  participates_in Organization, :members,
                  score: -> { Familia.now.to_f },
                  through: :Membership
end

puts '=== 1. Model Setup ==='
puts
puts 'Through model (Membership) requirements:'
puts '  • feature :object_identifier - enables deterministic keys'
puts '  • Fields for foreign keys: organization_objid, user_objid'
puts '  • Additional fields: role, permissions, invited_by, etc.'
puts
puts 'Participant (User) declaration:'
puts '  participates_in Organization, :members,'
puts '                  score: -> { Familia.now.to_f },'
puts '                  through: :Membership'
puts

# ============================================================================
# CREATING OBJECTS
# ============================================================================

puts '=== 2. Creating Objects ==='

org = Organization.new(name: 'Acme Corp', plan: 'enterprise')
org.save
puts "Created organization: #{org.name} (#{org.objid})"

alice = User.new(email: 'alice@acme.com', name: 'Alice')
alice.save
puts "Created user: #{alice.name} (#{alice.objid})"

bob = User.new(email: 'bob@acme.com', name: 'Bob')
bob.save
puts "Created user: #{bob.name} (#{bob.objid})"

charlie = User.new(email: 'charlie@acme.com', name: 'Charlie')
charlie.save
puts "Created user: #{charlie.name} (#{charlie.objid})"
puts

# ============================================================================
# ADDING MEMBERS WITH THROUGH ATTRIBUTES
# ============================================================================

puts '=== 3. Adding Members with Roles ==='
puts

# Add Alice as owner - through_attrs sets Membership fields
membership_alice = org.add_members_instance(alice, through_attrs: {
                                              role: 'owner',
  permissions: 'all',
  joined_at: Familia.now.to_f,
                                            })

puts "Added #{alice.name} as #{membership_alice.role}"
puts "  Membership objid: #{membership_alice.objid}"
puts "  Membership class: #{membership_alice.class.name}"
puts

# Add Bob as admin
membership_bob = org.add_members_instance(bob, through_attrs: {
                                            role: 'admin',
  permissions: 'read,write,invite',
  invited_by: alice.objid,
  invited_at: Familia.now.to_f,
  joined_at: Familia.now.to_f,
                                          })

puts "Added #{bob.name} as #{membership_bob.role}"
puts "  Invited by: #{membership_bob.invited_by}"
puts

# Add Charlie as member
membership_charlie = org.add_members_instance(charlie, through_attrs: {
                                                role: 'member',
  permissions: 'read',
  invited_by: bob.objid,
  invited_at: Familia.now.to_f,
  joined_at: Familia.now.to_f,
                                              })

puts "Added #{charlie.name} as #{membership_charlie.role}"
puts

# ============================================================================
# QUERYING MEMBERSHIPS
# ============================================================================

puts '=== 4. Querying Memberships ==='
puts

# Check organization members
puts "Organization #{org.name} has #{org.members.size} members:"
org.members.members.each do |user_id|
  puts "  - #{user_id}"
end
puts

# Check if user is member
puts "Is Alice a member? #{alice.in_organization_members?(org)}"
puts "Is Bob a member? #{bob.in_organization_members?(org)}"
puts

# Load and inspect through model directly
# Key format: {target_prefix}:{target_objid}:{participant_prefix}:{participant_objid}:{through_prefix}
membership_key = "organization:#{org.objid}:user:#{alice.objid}:membership"
loaded_membership = Membership.load(membership_key)

puts 'Direct membership lookup for Alice:'
puts "  Key: #{membership_key}"
puts "  Role: #{loaded_membership.role}"
puts "  Permissions: #{loaded_membership.permissions}"
puts "  Updated at: #{Time.at(loaded_membership.updated_at.to_f)}"
puts

# ============================================================================
# UPDATING MEMBERSHIP ATTRIBUTES
# ============================================================================

puts '=== 5. Updating Membership (Idempotent) ==='
puts

# Re-adding with different attrs updates the existing membership
puts "Promoting #{charlie.name} from member to admin..."

updated_membership = org.add_members_instance(charlie, through_attrs: {
                                                role: 'admin',
  permissions: 'read,write',
                                              })

puts "  New role: #{updated_membership.role}"
puts "  Same objid? #{updated_membership.objid == membership_charlie.objid}"
puts '  (Idempotent: updates existing, no duplicates)'
puts

# ============================================================================
# REMOVING MEMBERS
# ============================================================================

puts '=== 6. Removing Members ==='
puts

puts "Removing #{charlie.name} from organization..."
org.remove_members_instance(charlie)

# Verify removal
puts "  Is Charlie still a member? #{charlie.in_organization_members?(org)}"

# Through model is also destroyed
removed_key = "organization:#{org.objid}:user:#{charlie.objid}:membership"
removed_membership = Membership.load(removed_key)
puts "  Membership record exists? #{removed_membership&.exists? || false}"
puts

# ============================================================================
# BACKWARD COMPATIBILITY
# ============================================================================

puts '=== 7. Backward Compatibility ==='
puts

# Define a relationship WITHOUT :through
class Project < Familia::Horreum
  logical_database 15
  feature :object_identifier
  feature :relationships
  identifier_field :objid
  field :name
end

class Task < Familia::Horreum
  logical_database 15
  feature :object_identifier
  feature :relationships
  identifier_field :objid
  field :title
  # No :through - works exactly as before
  participates_in Project, :tasks, score: -> { Familia.now.to_f }
end

project = Project.new(name: 'Website Redesign')
project.save

task = Task.new(title: 'Design mockups')
task.save

# Without :through, returns the target (not a through model)
result = project.add_tasks_instance(task)
puts "Without :through, add returns: #{result.class.name}"
puts '  (Returns the target, not a through model)'
puts

# ============================================================================
# CLEANUP
# ============================================================================

puts '=== 8. Cleanup ==='

[org, alice, bob, charlie, project, task].each do |obj|
  obj.destroy! if obj&.exists?
end
puts 'Cleaned up all test objects'
puts
