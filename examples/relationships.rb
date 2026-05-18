#!/usr/bin/env ruby
# examples/relationships.rb
#
# frozen_string_literal: true

# Basic Relationships Example
# This example demonstrates the core features of Familia's relationships system

require 'familia'

# Configure Familia for the example
# Note: Individual models can specify logical_database if needed
Familia.configure do |config|
  config.uri = ENV.fetch('REDIS_URL', 'redis://localhost:2525/')
end

puts '=== Familia Relationships Basic Example ==='
puts

# Define our model classes
class Customer < Familia::Horreum
  logical_database 15 # Use test database
  feature :relationships

  identifier_field :custid
  field :custid
  field :name
  field :email
  field :plan

  # Define collections for tracking relationships
  set :domains           # Simple set of domain IDs
  listkey :projects      # Ordered list of project IDs
  sorted_set :activity   # Activity feed with timestamps

  # Class-level indexes for fast lookups. Both auto-populate on save.
  #   unique_index: 1:1 mapping  -> Customer.find_by_email(value) => Customer | nil
  #   multi_index:  1:many group -> Customer.find_all_by_plan(value) => [Customer, ...]
  unique_index :email, :email_lookup
  multi_index :plan, :plan_lookup

  # Every Horreum subclass already has a built-in `instances` sorted set
  # (a last-write timeline of all saved records), so there is no need to
  # declare a separate class-level "all customers" collection.
end

class Domain < Familia::Horreum
  logical_database 15 # Use test database
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :name
  field :dns_zone
  field :status

  # Declare membership in customer collections
  participates_in Customer, :domains # , type: :set

  # Track domains by status (using class_ prefix for class-level)
  class_participates_in :active_domains,
                        score: -> { status == 'active' ? Familia.now.to_i : 0 }
end

class Project < Familia::Horreum
  logical_database 15 # Use test database
  feature :relationships

  identifier_field :project_id
  field :project_id
  field :name
  field :priority

  # Member of customer projects list (ordered)
  participates_in Customer, :projects, type: :list
end

puts '=== 1. Basic Object Creation ==='

# Create some sample objects
customer = Customer.new(
  custid: "cust_#{SecureRandom.hex(4)}",
  name: 'Acme Corporation',
  email: 'admin@acme.com',
  plan: 'enterprise'
)

domain1 = Domain.new(
  domain_id: "dom_#{SecureRandom.hex(4)}",
  name: 'acme.com',
  dns_zone: 'acme.com.',
  status: 'active'
)

domain2 = Domain.new(
  domain_id: "dom_#{SecureRandom.hex(4)}",
  name: 'staging.acme.com',
  dns_zone: 'staging.acme.com.',
  status: 'active'
)

project = Project.new(
  project_id: "proj_#{SecureRandom.hex(4)}",
  name: 'Website Redesign',
  priority: 'high'
)

puts "✓ Created customer: #{customer.name} (#{customer.custid})"
puts "✓ Created domains: #{domain1.name}, #{domain2.name}"
puts "✓ Created project: #{project.name}"
puts

puts '=== 2. Establishing Relationships ==='

# Save objects to automatically update indexes and class-level tracking
customer.save # Auto-populates email_lookup, plan_lookup, and the instances timeline
puts '✓ Customer automatically added to indexes and tracking on save'

# Establish participates_in relationships using clean << operator syntax
customer.domains << domain1   # Clean Ruby-like syntax
customer.domains << domain2   # Same as domain1.add_to_customer_domains(customer)
customer.projects << project  # Same as project.add_to_customer_projects(customer)

puts '✓ Established domain ownership relationships using << operator'
puts '✓ Established project ownership relationships using << operator'

# Save domains. NOTE: save auto-populates indexes (unique_index/multi_index)
# and the instances timeline, but class_participates_in collections are NOT
# auto-populated -- they must be added explicitly.
domain1.save
domain2.save

# Add to the active_domains class collection. The score proc
# (status == 'active' ? timestamp : 0) is evaluated per domain.
Domain.add_to_active_domains(domain1)
Domain.add_to_active_domains(domain2)
puts '✓ Domains added to active_domains class collection'
puts

puts '=== 3. Querying Relationships ==='

# unique_index generates find_by_<field>, returning a single record (or nil)
record = Customer.find_by_email('admin@acme.com')
puts "Email lookup (unique_index): #{record&.custid || 'not found'}"

# multi_index generates find_all_by_<field>, returning an array of records
enterprise_customers = Customer.find_all_by_plan('enterprise')
puts "Plan lookup (multi_index): #{enterprise_customers.size} enterprise customer(s)"
puts

# Test membership queries
puts "\nDomain membership checks:"
puts "  #{domain1.name} belongs to customer? #{domain1.in_customer_domains?(customer)}"
puts "  #{domain2.name} belongs to customer? #{domain2.in_customer_domains?(customer)}"

puts "\nCustomer collections:"
puts "  Customer has #{customer.domains.size} domains"
puts "  Customer has #{customer.projects.size} projects"
puts "  Domain IDs: #{customer.domains.members}"
puts "  Project IDs: #{customer.projects.members}"

# The built-in `instances` sorted set tracks every saved record
all_customers_count = Customer.instances.size
puts "\nClass-level tracking:"
puts "  Total customers in system: #{all_customers_count}"

active_domains_count = Domain.active_domains.size
puts "  Active domains in system: #{active_domains_count}"
puts

puts '=== 4. Range Queries ==='

# Get recent customers (last 24 hours) from the instances timeline
yesterday = (Familia.now - (24 * 3600)).to_i # 24 hours ago
recent_customers = Customer.instances.rangebyscore(yesterday, '+inf')
puts "Recent customers (last 24h): #{recent_customers.size}"

# List active domains with their activation timestamps. The score is the
# value produced by the class_participates_in score proc. Look it up by
# passing the domain object to SortedSet#score (the serialization used when
# adding members matches object lookups, not bare id strings).
puts 'Active domains with timestamps:'
[domain1, domain2].each do |d|
  score = Domain.active_domains.score(d)
  next unless score

  puts "  #{d.name} (#{d.domain_id}): active since #{Time.at(score.to_i)} (score=#{score})"
end
puts

puts '=== 6. Relationship Cleanup ==='

# Remove relationships
puts 'Cleaning up relationships...'

# Remove from participates_in relationships
domain1.remove_from_customer_domains(customer)
puts "✓ Removed #{domain1.name} from customer domains"

# Remove from tracking collections
Domain.active_domains.remove(domain2)
puts "✓ Removed #{domain2.name} from active domains"

# Verify cleanup
puts "\nAfter cleanup:"
puts "  Customer domains: #{customer.domains.size}"
puts "  Active domains: #{Domain.active_domains.size}"
puts

# Purge all keys created by this example so it can be re-run safely.
# unique_index enforces uniqueness, so leftover records would collide on
# the next run with a RecordExistsError.
puts '=== Cleaning up test data ==='
[Customer, Domain, Project].each do |klass|
  keys = klass.dbclient.keys("#{klass.config_name}:*")
  klass.dbclient.del(*keys) unless keys.empty?
  puts "✓ Cleaned #{klass.name} (#{keys.length} keys)"
rescue StandardError => e
  puts "✗ Error cleaning #{klass.name}: #{e.message}"
end
puts

puts '=== Example Complete! ==='
puts
puts 'Key takeaways:'
puts '• unique_index: 1:1 class-level index -> find_by_<field> (single record)'
puts '• multi_index: 1:many class-level index -> find_all_by_<field> (array)'
puts '• instances: Built-in per-class timeline, auto-updated on every save'
puts '• unique_index/multi_index: Auto-populated on save'
puts '• class_participates_in: Class-level collections; add explicitly (not auto on save)'
puts '• participates_in: Use << operator for clean Ruby-like collection syntax'
puts '• Pass within: to unique_index/multi_index for relationship-scoped indexes'
puts '• << operator: Works naturally with all collection types (sets, lists, sorted sets)'
puts
puts 'See docs/wiki/Relationships-Guide.md for comprehensive documentation'
