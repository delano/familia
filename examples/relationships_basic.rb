#!/usr/bin/env ruby

# Basic Relationships Example
# This example demonstrates the core features of Familia's relationships system

require_relative '../lib/familia'

# Configure Familia for the example
# Note: Individual models can specify logical_database if needed

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

  # Create indexes for fast lookups (using new class_ prefix for global)
  class_indexed_by :email, :email_lookup # i.e. Customer.email_lookup
  class_indexed_by :plan, :plan_lookup # i.e. Customer.plan_lookup

  # Track in class-level collections (using new class_ prefix for global)
  class_tracked_in :all_customers, score: :created_at # i.e. Customer.all_customers

  def created_at
    Time.now.to_i
  end
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
  member_of Customer, :domains, type: :set

  # Track domains by status (using new class_ prefix for global)
  class_tracked_in :active_domains,
                   score: -> { status == 'active' ? Time.now.to_i : 0 }
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

# Add objects to indexed lookups (use instance methods for indexing)
# TODO: The customer should be automatically added to these lookups when
# the record is created with Customer.create (e.g. via Customer.add).
customer.add_to_class_email_lookup
customer.add_to_class_plan_lookup
puts '✓ Added customer to email and plan indexes'

# Add customer to class-level tracking
Customer.add_to_all_customers(customer)
puts '✓ Added customer to class-level customer tracking'

# Establish member_of relationships (bidirectional)
domain1.add_to_customer_domains(customer)
customer.domains.add(domain1.identifier)

domain2.add_to_customer_domains(customer)
customer.domains.add(domain2.identifier)

project.add_to_customer_projects(customer)
customer.projects.add(project.identifier)

puts '✓ Established domain ownership relationships'
puts '✓ Established project ownership relationships'

# Track domains in status collections
Domain.add_to_active_domains(domain1)
Domain.add_to_active_domains(domain2)
puts '✓ Added domains to active tracking'
puts

puts '=== 3. Querying Relationships ==='

# Test indexed lookups using class-level finder methods
begin
  found_customer = Customer.find_by_email(customer.email)
  puts "Email lookup for #{customer.email}: #{found_customer ? found_customer.custid : 'not found'}"
rescue NoMethodError => e
  puts "Index lookup not yet available: #{e.message.split(' for ').first}"
end

begin
  enterprise_customer = Customer.find_by_plan('enterprise')
  puts "Enterprise customer found: #{enterprise_customer ? enterprise_customer.custid : 'not found'}"
rescue NoMethodError => e
  puts "Index lookup not yet available: #{e.message.split(' for ').first}"
end

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
all_customers_count = Customer.all_customers.size
puts "\nClass-level tracking:"
puts "  Total customers in system: #{all_customers_count}"

active_domains_count = Domain.active_domains.size
puts "  Active domains in system: #{active_domains_count}"
puts

puts '=== 4. Range Queries ==='

# Get recent customers (last 24 hours)
yesterday = (Time.now - (24 * 3600)).to_i # 24 hours ago
recent_customers = Customer.all_customers.rangebyscore(yesterday, '+inf')
puts "Recent customers (last 24h): #{recent_customers.size}"

# Get all active domains by score
active_domain_scores = Domain.active_domains.rangebyscore(1, '+inf', with_scores: true)
puts 'Active domains with timestamps:'
active_domain_scores.each do |domain_id, timestamp|
  puts "  #{domain_id}: active since #{Time.at(timestamp.to_i)}"
end
puts

puts '=== 5. Batch Operations ==='

# Create additional test data
additional_customers = []
3.times do |i|
  cust = Customer.new(
    custid: "batch_cust_#{i}",
    name: "Customer #{i}",
    email: "customer#{i}@example.com",
    plan: i.even? ? 'basic' : 'premium'
  )
  additional_customers << cust

  # Add to indexes and tracking
  cust.add_to_class_email_lookup
  cust.add_to_class_plan_lookup
  Customer.add_to_all_customers(cust)
end

puts "✓ Created and indexed #{additional_customers.size} additional customers"

# Query by plan (wrapped in error handling)
begin
  basic_customer = Customer.find_by_plan('basic')
  premium_customer = Customer.find_by_plan('premium')
  enterprise_customer = Customer.find_by_plan('enterprise')

  puts "\nCustomer distribution by plan:"
  puts "  Basic: #{basic_customer ? 1 : 0} customers"
  puts "  Premium: #{premium_customer ? 1 : 0} customers"
  puts "  Enterprise: #{enterprise_customer ? 1 : 0} customers"
rescue NoMethodError
  puts "\nIndex lookup functionality not yet fully implemented"
end
puts

puts '=== 6. Relationship Cleanup ==='

# Remove relationships
puts 'Cleaning up relationships...'

# Remove from member_of relationships
# TODO: Look into why we are making two calls here instead of just one? Why
# doesn;t the call to remove_from_customer_domains remove it from customer.domains
# (or vice versa).
domain1.remove_from_customer_domains(customer)
customer.domains.remove(domain1.identifier)
puts "✓ Removed #{domain1.name} from customer domains"

# Remove from tracking collections
Domain.active_domains.remove(domain2.identifier)
puts "✓ Removed #{domain2.name} from active domains"

# Verify cleanup
puts "\nAfter cleanup:"
puts "  Customer domains: #{customer.domains.size}"
puts "  Active domains: #{Domain.active_domains.size}"
puts

puts '=== 7. Advanced Usage - Permission Encoding ==='

# Demonstrate basic score encoding for permissions
class DocumentAccess
  # Permission flags (powers of 2)
  READ = 1
  WRITE = 2
  DELETE = 4
  ADMIN = 8

  def self.encode_permissions(timestamp, permissions)
    "#{timestamp}.#{permissions}".to_f
  end

  def self.decode_permissions(score)
    parts = score.to_s.split('.')
    timestamp = parts[0].to_i
    permissions = parts[1] ? parts[1].to_i : 0
    [timestamp, permissions]
  end
end

# Example permission encoding
now = Time.now.to_i
read_write_permissions = DocumentAccess::READ | DocumentAccess::WRITE # 3
DocumentAccess::ADMIN # 8

encoded_score = DocumentAccess.encode_permissions(now, read_write_permissions)
timestamp, permissions = DocumentAccess.decode_permissions(encoded_score)

puts 'Permission encoding example:'
puts "  Original: timestamp=#{now}, permissions=#{read_write_permissions}"
puts "  Encoded score: #{encoded_score}"
puts "  Decoded: timestamp=#{timestamp}, permissions=#{permissions}"
puts "  Has read access: #{permissions.anybits?(DocumentAccess::READ)}"
puts "  Has write access: #{permissions.anybits?(DocumentAccess::WRITE)}"
puts "  Has delete access: #{permissions.anybits?(DocumentAccess::DELETE)}"
puts

puts '=== Example Complete! ==='
puts
puts 'Key takeaways:'
puts '• tracked_in: Use for activity feeds, leaderboards, time-series data'
puts '• indexed_by: Use for fast O(1) lookups by field values'
puts '• member_of: Use for bidirectional ownership/membership'
puts '• Score encoding: Combine timestamps with metadata for rich queries'
puts '• Batch operations: Use Redis pipelines for efficiency'
puts
puts 'See docs/wiki/Relationships-Guide.md for comprehensive documentation'
