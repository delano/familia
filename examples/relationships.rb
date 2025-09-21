#!/usr/bin/env ruby

# Basic Relationships Example
# This example demonstrates the core features of Familia's relationships system

require 'familia'

# Configure Familia for the example
# Note: Individual models can specify logical_database if needed
Familia.configure do |config|
  config.uri = 'redis://localhost:6379/'
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
  list :projects         # Ordered list of project IDs
  sorted_set :activity   # Activity feed with timestamps

  # Create indexes for fast lookups (using class_ prefix for class-level)
  class_indexed_by :email, :email_lookup # i.e. Customer.email_lookup
  class_indexed_by :plan, :plan_lookup # i.e. Customer.plan_lookup

  # Track in class-level collections (using class_ prefix for class-level)
  class_tracked_in :all_customers, score: :created_at # i.e. Customer.all_customers
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
  member_of Customer, :domains # , type: :set

  # Track domains by status (using class_ prefix for class-level)
  class_tracked_in :active_domains,
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
  member_of Customer, :projects, type: :list
end

puts '=== 1. Basic Object Creation ==='

# Create some sample objects
customer = Customer.new(
  # custid: "cust_#{SecureRandom.hex(4)}",
  name: 'Acme Corporation',
  email: 'admin@acme.com',
  plan: 'enterprise'
)

domain1 = Domain.new(
  # domain_id: "dom_#{SecureRandom.hex(4)}",
  name: 'acme.com',
  dns_zone: 'acme.com.',
  status: 'active'
)

domain2 = Domain.new(
  # domain_id: "dom_#{SecureRandom.hex(4)}",
  name: 'staging.acme.com',
  dns_zone: 'staging.acme.com.',
  status: 'active'
)

project = Project.new(
  # project_id: "proj_#{SecureRandom.hex(4)}",
  name: 'Website Redesign',
  priority: 'high'
)

puts "✓ Created customer: #{customer.name} (#{customer.custid})"
puts "✓ Created domains: #{domain1.name}, #{domain2.name}"
puts "✓ Created project: #{project.name}"
puts

puts '=== 2. Establishing Relationships ==='

# Save objects to automatically update indexes and class-level tracking
customer.save # Automatically adds to email_lookup, plan_lookup, and all_customers
puts '✓ Customer automatically added to indexes and tracking on save'

# Establish member_of relationships using clean << operator syntax
customer.domains << domain1   # Clean Ruby-like syntax
customer.domains << domain2   # Same as domain1.add_to_customer_domains(customer)
customer.projects << project  # Same as project.add_to_customer_projects(customer)

puts '✓ Established domain ownership relationships using << operator'
puts '✓ Established project ownership relationships using << operator'

# Save domains to automatically add them to class-level tracking
domain1.save  # Automatically adds to active_domains if status == 'active'
domain2.save  # Automatically adds to active_domains if status == 'active'
puts '✓ Domains automatically added to status tracking on save'
puts

puts '=== 3. Querying Relationships ==='

record = Customer.get_by_email('admin@acme.com')
puts "Email lookup: #{record&.custid || 'not found'}"

Customer.get_by_plan('enterprise') # raises MoreThanOne

results = Customer.find_by_email('admin@acme.com')
puts "Email lookup: #{results&.size} found"

results = Customer.find_by_plan('enterprise')
puts "Enterprise lookup: #{results&.size} found"
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

# Test tracked_in collections
all_customers_count = Customer.values.size
puts "\nClass-level tracking:"
puts "  Total customers in system: #{all_customers_count}"

active_domains_count = Domain.active_domains.size
puts "  Active domains in system: #{active_domains_count}"
puts

puts '=== 4. Range Queries ==='

# Get recent customers (last 24 hours)
yesterday = (Familia.now - (24 * 3600)).to_i # 24 hours ago
recent_customers = Customer.values.rangebyscore(yesterday, '+inf')
puts "Recent customers (last 24h): #{recent_customers.size}"

# Get all active domains by score
active_domain_scores = Domain.active_domains.rangebyscore(1, '+inf', with_scores: true)
puts 'Active domains with timestamps:'
active_domain_scores.each_slice(2) do |domain_id, timestamp|
  puts "  #{domain_id}: active since #{Time.at(timestamp.to_i)} #{timestamp.inspect}"
end
puts

puts '=== 6. Relationship Cleanup ==='

# Remove relationships
puts 'Cleaning up relationships...'

# Remove from member_of relationships
domain1.remove_from_customer_domains(customer)
puts "✓ Removed #{domain1.name} from customer domains"

# Remove from tracking collections
Domain.active_domains.remove(domain2.identifier)
puts "✓ Removed #{domain2.name} from active domains"

# Verify cleanup
puts "\nAfter cleanup:"
puts "  Customer domains: #{customer.domains.size}"
puts "  Active domains: #{Domain.active_domains.size}"
puts

puts '=== Example Complete! ==='
puts
puts 'Key takeaways:'
puts '• class_tracked_in: Automatic class-level collections updated on save'
puts '• class_indexed_by: Automatic class-level indexes updated on save'
puts '• member_of: Use << operator for clean Ruby-like collection syntax'
puts '• indexed_by with context:: Use for relationship-scoped indexes'
puts '• Save operations: Automatically update indexes and class-level tracking'
puts '• << operator: Works naturally with all collection types (sets, lists, sorted sets)'
puts
puts 'See docs/wiki/Relationships-Guide.md for comprehensive documentation'
