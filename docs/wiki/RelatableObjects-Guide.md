# RelatableObjects Guide

## Overview

The RelatableObjects feature provides a standardized system for managing object relationships and ownership in Familia applications. It enables objects to have unique identifiers, external references, and ownership relationships while maintaining API versioning and secure object management.

## Core Concepts

### Object Identity System

RelatableObjects introduces a dual-identifier system:

1. **Object ID (`objid`)**: Internal UUID v7 for system use
2. **External ID (`extid`)**: External-facing identifier for API consumers

### Ownership Model

Objects can own other objects through a centralized ownership registry:
- **Owners**: Objects that possess other objects
- **Owned Objects**: Objects that belong to other objects  
- **Ownership Validation**: Prevents self-ownership and enforces type checking

## Basic Usage

### Enabling RelatableObjects

```ruby
class Customer < Familia::Horreum
  feature :relatable_object  # Note: uses relatable_object, not relatable_objects
  
  field :name, :email, :plan
end

class Domain < Familia::Horreum
  feature :relatable_object
  
  field :name, :dns_zone
end
```

### Automatic ID Generation

```ruby
customer = Customer.new(name: "Acme Corp", email: "admin@acme.com")

# IDs are lazily generated on first access
customer.objid   # => "018c3f8e-7b2a-7f4a-9d8e-1a2b3c4d5e6f" (UUID v7)
customer.extid   # => "ext_3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z" (54 chars)

# Alternative accessor methods
customer.relatable_objid       # Same as objid  
customer.external_identifier   # Same as extid

# API version tracking
customer.api_version  # => "v2" (automatically set)
```

### Object Relationships

```ruby
# Establish ownership
customer = Customer.find_by_objid("018c3f8e-7b2a-7f4a-9d8e-1a2b3c4d5e6f")
domain = Domain.new(name: "acme.com")

# Set ownership (must be implemented by your application)
Customer.owners.set(domain.objid, customer.objid)

# Check ownership  
domain.owner?(customer)  # => true
domain.owned?           # => true
customer.owner?(domain) # => false (customers don't have owners in this example)

# Find owner
owner_objid = Customer.owners.get(domain.objid)
owner = Customer.find_by_objid(owner_objid)
```

## Advanced Features

### Custom Identifier Generation

```ruby
# Override ID generation for custom formats
class CustomModel < Familia::Horreum
  feature :relatable_object
  
  def self.generate_objid
    # Custom UUID generation
    "custom_#{SecureRandom.uuid_v7}"
  end
  
  def self.generate_extid
    # Custom external ID format
    "ext_#{Time.now.to_i}_#{SecureRandom.hex(8)}"
  end
end
```

### Ownership Management System

```ruby
class OwnershipManager
  # Grant ownership
  def self.assign_owner(owned_object, owner_object)
    # Validate objects are relatable
    raise "Not relatable" unless owned_object.is_a?(V2::Features::RelatableObject)
    raise "Not relatable" unless owner_object.is_a?(V2::Features::RelatableObject)
    
    # Prevent self-ownership  
    raise "Self-ownership not allowed" if owned_object.class == owner_object.class
    
    # Set ownership in registry
    owner_object.class.owners.set(owned_object.objid, owner_object.objid)
  end
  
  # Remove ownership
  def self.remove_owner(owned_object)
    owned_object.class.owners.delete(owned_object.objid)
  end
  
  # Transfer ownership
  def self.transfer_ownership(owned_object, new_owner)
    remove_owner(owned_object)
    assign_owner(owned_object, new_owner)
  end
  
  # Get owner
  def self.get_owner(owned_object, owner_class)
    owner_objid = owned_object.class.owners.get(owned_object.objid)
    return nil if owner_objid.nil? || owner_objid.empty?
    
    owner_class.find_by_objid(owner_objid)
  end
end

# Usage
customer = Customer.new(name: "Acme Corp")
domain = Domain.new(name: "acme.com")

OwnershipManager.assign_owner(domain, customer)
OwnershipManager.get_owner(domain, Customer)  # => customer object
```

### Multi-Tenant Patterns

```ruby
class Organization < Familia::Horreum
  feature :relatable_object
  
  field :name, :plan, :domain
  
  def users
    User.owned_by(self)
  end
  
  def projects
    Project.owned_by(self) 
  end
end

class User < Familia::Horreum
  feature :relatable_object
  
  field :email, :name, :role
  
  def self.owned_by(organization)
    owned_objids = owners.keys.select do |user_objid|
      owners.get(user_objid) == organization.objid
    end
    
    owned_objids.map { |objid| find_by_objid(objid) }.compact
  end
  
  def organization
    org_objid = self.class.owners.get(objid)
    Organization.find_by_objid(org_objid)
  end
end

class Project < Familia::Horreum
  feature :relatable_object
  
  field :name, :description, :status
  
  def self.owned_by(organization)
    # Similar implementation as User.owned_by
  end
end

# Usage
org = Organization.create(name: "Acme Corp")
user = User.create(email: "john@acme.com", name: "John Doe")
project = Project.create(name: "Website Redesign")

OwnershipManager.assign_owner(user, org)
OwnershipManager.assign_owner(project, org)

org.users     # => [user]
org.projects  # => [project]
user.organization  # => org
```

### API Integration Patterns

```ruby
class APIController
  # Use external IDs in API responses
  def show_customer
    customer = Customer.find_by_objid(params[:objid])  # Internal lookup
    
    render json: {
      id: customer.extid,           # External ID for API consumers
      name: customer.name,
      email: customer.email,
      api_version: customer.api_version,
      domains: customer_domains(customer)
    }
  end
  
  # Accept external IDs in API requests
  def update_customer
    # Convert external ID to internal lookup
    extid = params[:id]
    objid = resolve_external_id(extid, Customer)
    customer = Customer.find_by_objid(objid)
    
    customer.update(customer_params)
    
    render json: { id: customer.extid, status: 'updated' }
  end
  
  private
  
  def customer_domains(customer)
    Domain.owned_by(customer).map do |domain|
      {
        id: domain.extid,
        name: domain.name,
        dns_zone: domain.dns_zone
      }
    end
  end
  
  def resolve_external_id(extid, klass)
    # Implementation depends on your external ID tracking system
    # This could be a separate mapping table or embedded in the extid format
    ExternalIdMapping.objid_for(extid, klass)
  end
end
```

## Object Lifecycle Management

### Creation with Relationships

```ruby
class CustomerCreationService
  def self.create_with_domain(customer_attrs, domain_name)
    customer = Customer.create(customer_attrs)
    domain = Domain.create(name: domain_name)
    
    # Establish ownership
    OwnershipManager.assign_owner(domain, customer)
    
    {
      customer: customer,
      domain: domain,
      customer_id: customer.extid,  # For API responses
      domain_id: domain.extid
    }
  end
end

# Usage
result = CustomerCreationService.create_with_domain(
  { name: "Acme Corp", email: "admin@acme.com" },
  "acme.com"
)

puts result[:customer_id]  # => "ext_3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z"
```

### Deletion with Cleanup

```ruby
class CustomerDeletionService
  def self.delete_with_owned_objects(customer)
    # Find all owned objects
    owned_domains = Domain.owned_by(customer)
    owned_users = User.owned_by(customer) 
    owned_projects = Project.owned_by(customer)
    
    # Delete owned objects first
    owned_domains.each(&:delete)
    owned_users.each(&:delete)
    owned_projects.each(&:delete)
    
    # Clean up ownership records
    [Domain, User, Project].each do |klass|
      cleanup_ownership_records(klass, customer)
    end
    
    # Finally delete the owner
    customer.delete
  end
  
  private
  
  def self.cleanup_ownership_records(owned_class, owner)
    # Remove ownership records where this customer was the owner
    owned_class.owners.keys.each do |owned_objid|
      if owned_class.owners.get(owned_objid) == owner.objid
        owned_class.owners.delete(owned_objid)
      end
    end
  end
end
```

## Security Considerations

### Access Control

```ruby
class SecureAccessManager
  def self.verify_ownership(user, resource)
    return false unless user.is_a?(V2::Features::RelatableObject)
    return false unless resource.is_a?(V2::Features::RelatableObject)
    
    # Check direct ownership
    return true if resource.owner?(user)
    
    # Check organizational ownership
    user_org = OwnershipManager.get_owner(user, Organization)
    return true if user_org && resource.owner?(user_org)
    
    false
  end
  
  def self.filter_owned_resources(user, resources)
    resources.select { |resource| verify_ownership(user, resource) }
  end
end

# In your controllers
class ResourceController
  before_action :authenticate_user
  before_action :load_resource, only: [:show, :update, :destroy]
  before_action :verify_access, only: [:show, :update, :destroy]
  
  private
  
  def load_resource
    @resource = Resource.find_by_objid(params[:objid])
    not_found unless @resource
  end
  
  def verify_access
    unless SecureAccessManager.verify_ownership(current_user, @resource)
      unauthorized
    end
  end
end
```

### External ID Security

```ruby
# Prevent external ID enumeration attacks
class SecureExternalIdGenerator
  def self.generate_secure_extid(objid)
    # Use HMAC to prevent guessing
    timestamp = Time.now.to_i
    data = "#{objid}:#{timestamp}"
    hmac = OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, data)
    
    "ext_#{timestamp}_#{hmac[0..15]}"  # 54 characters total
  end
  
  def self.validate_extid(extid, objid)
    # Verify HMAC to prevent tampering
    parts = extid.split('_')
    return false unless parts.length == 3 && parts[0] == 'ext'
    
    timestamp, provided_hmac = parts[1], parts[2]
    expected_data = "#{objid}:#{timestamp}"
    expected_hmac = OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, expected_data)
    
    expected_hmac[0..15] == provided_hmac
  end
end

# Override in your models
class SecureCustomer < Familia::Horreum
  feature :relatable_object
  
  def self.generate_extid
    # Will be called after objid is generated
    SecureExternalIdGenerator.generate_secure_extid(objid)
  end
end
```

## Performance Optimization

### Batch Operations

```ruby
class BatchOwnershipManager
  def self.assign_multiple_owners(ownership_pairs)
    # ownership_pairs: [{ owned: obj1, owner: obj2 }, ...]
    
    # Group by owner class to minimize pipe operations
    grouped = ownership_pairs.group_by { |pair| pair[:owner].class }
    
    grouped.each do |owner_class, pairs|
      owner_class.owners.pipeline do |pipe|
        pairs.each do |pair|
          pipe.hset(pair[:owned].objid, pair[:owner].objid)
        end
      end
    end
  end
  
  def self.load_owners_for_objects(objects, owner_class)
    return {} if objects.empty?
    
    # Batch load all ownership records
    objids = objects.map(&:objid)
    owner_objids = owner_class.owners.mget(*objids)
    
    # Batch load owner objects
    valid_owner_objids = owner_objids.compact.uniq
    owners = valid_owner_objids.map { |objid| owner_class.find_by_objid(objid) }.compact
    owners_by_objid = owners.index_by(&:objid)
    
    # Create mapping
    objects.zip(owner_objids).to_h do |obj, owner_objid|
      [obj, owner_objid ? owners_by_objid[owner_objid] : nil]
    end
  end
end

# Usage
domains = Domain.all
domain_owners = BatchOwnershipManager.load_owners_for_objects(domains, Customer)

domains.each do |domain|
  owner = domain_owners[domain]
  puts "#{domain.name} owned by #{owner&.name || 'nobody'}"
end
```

### Caching Strategies

```ruby
class CachedOwnershipLookup
  CACHE_TTL = 5.minutes
  
  def self.get_owner(owned_object, owner_class)
    cache_key = "owner:#{owned_object.objid}:#{owner_class.name}"
    
    cached = Rails.cache.read(cache_key)
    return cached if cached
    
    owner = OwnershipManager.get_owner(owned_object, owner_class)
    Rails.cache.write(cache_key, owner, expires_in: CACHE_TTL)
    
    owner
  end
  
  def self.invalidate_ownership_cache(owned_object)
    # Invalidate all possible owner class caches
    [Customer, Organization, User].each do |owner_class|
      cache_key = "owner:#{owned_object.objid}:#{owner_class.name}"
      Rails.cache.delete(cache_key)
    end
  end
end
```

## Testing

### RSpec Testing

```ruby
RSpec.describe RelatableObject do
  let(:customer) { Customer.create(name: "Test Customer") }
  let(:domain) { Domain.create(name: "test.com") }
  
  describe "ID generation" do
    it "generates UUID v7 for objid" do
      expect(customer.objid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
    end
    
    it "generates 54-character external ID" do
      expect(customer.extid).to start_with('ext_')
      expect(customer.extid.length).to eq(54)
    end
  end
  
  describe "ownership" do
    before do
      OwnershipManager.assign_owner(domain, customer)
    end
    
    it "establishes ownership relationship" do
      expect(domain.owner?(customer)).to be true
      expect(domain.owned?).to be true
    end
    
    it "prevents self-ownership" do
      expect {
        OwnershipManager.assign_owner(customer, customer)
      }.to raise_error(/self-ownership/i)
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe "RelatableObjects Integration" do
  scenario "multi-tenant customer with domains and users" do
    # Create organization
    org = Organization.create(name: "Acme Corp")
    
    # Create users and domains
    user1 = User.create(email: "john@acme.com")
    user2 = User.create(email: "jane@acme.com")
    domain = Domain.create(name: "acme.com")
    
    # Establish ownership
    OwnershipManager.assign_owner(user1, org)
    OwnershipManager.assign_owner(user2, org)  
    OwnershipManager.assign_owner(domain, org)
    
    # Verify relationships
    expect(org.users).to contain_exactly(user1, user2)
    expect(org.domains).to contain_exactly(domain)
    expect(user1.organization).to eq(org)
    expect(domain.owner?(org)).to be true
    
    # Test access control
    expect(SecureAccessManager.verify_ownership(user1, domain)).to be true
    expect(SecureAccessManager.verify_ownership(user2, domain)).to be true
  end
end
```

## Best Practices

1. **Consistent ID Usage**: Always use external IDs in APIs, internal objids for system operations
2. **Ownership Validation**: Validate ownership before allowing operations
3. **Batch Operations**: Use batch loading for performance when dealing with multiple objects
4. **Cache Appropriately**: Cache ownership lookups but invalidate on changes  
5. **Secure External IDs**: Use HMACs or similar to prevent ID enumeration attacks
6. **Clean Deletion**: Always clean up ownership records when deleting objects
7. **Type Safety**: Validate object types in ownership operations
8. **API Versioning**: Use the api_version field to handle API evolution

The RelatableObjects feature provides a robust foundation for building multi-tenant applications with secure object relationships and clear ownership models.