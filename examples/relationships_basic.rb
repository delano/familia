#!/usr/bin/env ruby

# Basic Relationships Example
# This example demonstrates the core features of Familia's relationships system

require_relative '../lib/familia'

# Configure Familia for the example
Familia.configure do |config|
  config.redis_uri = ENV.fetch('REDIS_URI', 'redis://localhost:6379/15')
end

puts "=== Familia Relationships Basic Example ==="
puts

# Define our model classes
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid, :name, :email, :plan

  # Define collections for tracking relationships
  set :domains           # Simple set of domain IDs
  list :projects         # Ordered list of project IDs
  sorted_set :activity   # Activity feed with timestamps

  # Create indexes for fast lookups
  indexed_by :email_lookup, field: :email
  indexed_by :plan_lookup, field: :plan

  # Track in global collections
  tracked_in :all_customers, type: :sorted_set, score: :created_at

  def created_at
    Time.now.to_i
  end
end

class Domain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id, :name, :dns_zone, :status

  # Declare membership in customer collections
  member_of Customer, :domains, type: :set

  # Track domains by status
  tracked_in :active_domains, type: :sorted_set,
    score: ->(domain) { domain.status == 'active' ? Time.now.to_i : 0 }
end

class Project < Familia::Horreum
  feature :relationships

  identifier_field :project_id
  field :project_id, :name, :priority

  # Member of customer projects list (ordered)
  member_of Customer, :projects, type: :list
end

puts "=== 1. Basic Object Creation ==="

# Create some sample objects
customer = Customer.new(
  custid: "cust_#{SecureRandom.hex(4)}",
  name: "Acme Corporation",
  email: "admin@acme.com",
  plan: "enterprise"
)

domain1 = Domain.new(
  domain_id: "dom_#{SecureRandom.hex(4)}",
  name: "acme.com",
  dns_zone: "acme.com.",
  status: "active"
)

domain2 = Domain.new(
  domain_id: "dom_#{SecureRandom.hex(4)}",
  name: "staging.acme.com",
  dns_zone: "staging.acme.com.",
  status: "active"
)

project = Project.new(
  project_id: "proj_#{SecureRandom.hex(4)}",
  name: "Website Redesign",
  priority: "high"
)

puts "✓ Created customer: #{customer.name} (#{customer.custid})"
puts "✓ Created domains: #{domain1.name}, #{domain2.name}"
puts "✓ Created project: #{project.name}"
puts

puts "=== 2. Establishing Relationships ==="

# Add objects to indexed lookups
Customer.add_to_email_lookup(customer)
Customer.add_to_plan_lookup(customer)
puts "✓ Added customer to email and plan indexes"

# Add customer to global tracking
Customer.add_to_all_customers(customer)
puts "✓ Added customer to global customer tracking"

# Establish member_of relationships (bidirectional)
domain1.add_to_customer_domains(customer.custid)
customer.domains.add(domain1.identifier)

domain2.add_to_customer_domains(customer.custid)
customer.domains.add(domain2.identifier)

project.add_to_customer_projects(customer.custid)
customer.projects.add(project.identifier)

puts "✓ Established domain ownership relationships"
puts "✓ Established project ownership relationships"

# Track domains in status collections
Domain.add_to_active_domains(domain1)
Domain.add_to_active_domains(domain2)
puts "✓ Added domains to active tracking"
puts

puts "=== 3. Querying Relationships ==="

# Test indexed lookups
found_customer_id = Customer.email_lookup.get(customer.email)
puts "Email lookup for #{customer.email}: #{found_customer_id}"

enterprise_customers = Customer.plan_lookup.get("enterprise")
puts "Enterprise customer found: #{enterprise_customers}"

# Test membership queries
puts "\nDomain membership checks:"
puts "  #{domain1.name} belongs to customer? #{domain1.in_customer_domains?(customer.custid)}"
puts "  #{domain2.name} belongs to customer? #{domain2.in_customer_domains?(customer.custid)}"

puts "\nCustomer collections:"
puts "  Customer has #{customer.domains.size} domains"
puts "  Customer has #{customer.projects.size} projects"
puts "  Domain IDs: #{customer.domains.members}"
puts "  Project IDs: #{customer.projects.members}"

# Test tracked_in collections
all_customers_count = Customer.all_customers.size
puts "\nGlobal tracking:"
puts "  Total customers in system: #{all_customers_count}"

active_domains_count = Domain.active_domains.size
puts "  Active domains in system: #{active_domains_count}"
puts

puts "=== 4. Range Queries ==="

# Get recent customers (last 24 hours)
yesterday = (Time.now - 24.hours).to_i
recent_customers = Customer.all_customers.range_by_score(yesterday, '+inf')
puts "Recent customers (last 24h): #{recent_customers.size}"

# Get all active domains by score
active_domain_scores = Domain.active_domains.range_by_score(1, '+inf', with_scores: true)
puts "Active domains with timestamps:"
active_domain_scores.each do |domain_id, timestamp|
  puts "  #{domain_id}: active since #{Time.at(timestamp.to_i)}"
end
puts

puts "=== 5. Batch Operations ==="

# Create additional test data
additional_customers = []
3.times do |i|
  cust = Customer.new(
    custid: "batch_cust_#{i}",
    name: "Customer #{i}",
    email: "customer#{i}@example.com",
    plan: i.even? ? "basic" : "premium"
  )
  additional_customers << cust

  # Add to indexes and tracking
  Customer.add_to_email_lookup(cust)
  Customer.add_to_plan_lookup(cust)
  Customer.add_to_all_customers(cust)
end

puts "✓ Created and indexed #{additional_customers.size} additional customers"

# Query by plan
basic_customers = Customer.plan_lookup.get("basic")
premium_customers = Customer.plan_lookup.get("premium")
enterprise_customers = Customer.plan_lookup.get("enterprise")

puts "\nCustomer distribution by plan:"
puts "  Basic: #{basic_customers ? 1 : 0} customers"
puts "  Premium: #{premium_customers ? 1 : 0} customers"
puts "  Enterprise: #{enterprise_customers ? 1 : 0} customers"
puts

puts "=== 6. Relationship Cleanup ==="

# Remove relationships
puts "Cleaning up relationships..."

# Remove from member_of relationships
domain1.remove_from_customer_domains(customer.custid)
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

puts "=== 7. Advanced Usage - Permission Encoding ==="

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
read_write_permissions = DocumentAccess::READ | DocumentAccess::WRITE  # 3
admin_permissions = DocumentAccess::ADMIN  # 8

encoded_score = DocumentAccess.encode_permissions(now, read_write_permissions)
timestamp, permissions = DocumentAccess.decode_permissions(encoded_score)

puts "Permission encoding example:"
puts "  Original: timestamp=#{now}, permissions=#{read_write_permissions}"
puts "  Encoded score: #{encoded_score}"
puts "  Decoded: timestamp=#{timestamp}, permissions=#{permissions}"
puts "  Has read access: #{(permissions & DocumentAccess::READ) != 0}"
puts "  Has write access: #{(permissions & DocumentAccess::WRITE) != 0}"
puts "  Has delete access: #{(permissions & DocumentAccess::DELETE) != 0}"
puts

puts "=== Example Complete! ==="
puts
puts "Key takeaways:"
puts "• tracked_in: Use for activity feeds, leaderboards, time-series data"
puts "• indexed_by: Use for fast O(1) lookups by field values"
puts "• member_of: Use for bidirectional ownership/membership"
puts "• Score encoding: Combine timestamps with metadata for rich queries"
puts "• Batch operations: Use Redis pipelines for efficiency"
puts
puts "See docs/wiki/Relationships-Guide.md for comprehensive documentation"
