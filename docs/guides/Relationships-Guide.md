# Relationships Guide

## Overview

The Relationships feature provides a sophisticated system for managing object relationships in Familia applications. It enables objects to track membership, create bidirectional associations, and maintain indexed lookups while supporting advanced features like permission bit encoding and time-based analytics.

## Core Concepts

### Relationship Types

The Familia v2.0 relationships system provides three distinct relationship patterns:

1. **`tracked_in`** - Multi-presence tracking with score encoding (sorted sets)
2. **`indexed_by`** - O(1) hash-based lookups by field values
3. **`member_of`** - Bidirectional membership with collision-free naming

Each type is optimized for different use cases and provides specific performance characteristics.

## Basic Usage

### Enabling Relationships

```ruby
class Customer < Familia::Horreum
  feature :relationships  # Enable relationship functionality

  identifier_field :custid
  field :custid, :name, :email

  # Define relationship collections
  class_tracked_in :active_users, score: :created_at
  class_indexed_by :email, :email_lookup
end

class Domain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id, :name, :dns_zone

  # Define bidirectional membership
  member_of Customer, :domains, type: :set
end
```

## Tracked In Relationships

### Basic Tracking

The `tracked_in` relationship creates collections that track object membership with sophisticated scoring:

```ruby
class User < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id, :name, :score_value

  # Simple sorted set tracking
  class_tracked_in :leaderboard, score: :score_value

  # Time-based tracking with automatic timestamps
  class_tracked_in :activity_log, score: :created_at

  # Proc-based scoring for complex calculations
  class_tracked_in :performance_metrics, score: -> { (score_value || 0) * 2 }
end

# Usage
user = User.new(user_id: 'user123', score_value: 85)

# Add to collections
User.add_to_leaderboard(user)              # Uses score_value (85)
User.add_to_activity_log(user)             # Uses created_at timestamp
User.add_to_performance_metrics(user)      # Uses proc result (170)

# Query collections
User.leaderboard.score('user123')           # => 85.0
User.activity_log.rangebyscore('-inf', '+inf')  # All users by time
User.performance_metrics.rank('user123')    # User's rank by performance
```

### Score Encoding System

The relationships feature includes a sophisticated bit encoding system for permissions and metadata:

```ruby
class Document < Familia::Horreum
  feature :relationships

  identifier_field :doc_id
  field :doc_id, :title, :content

  # Permission-based tracking with 8-bit encoding
  class_tracked_in :authorized_users, score: :encode_permissions

  private

  def encode_permissions
    # Combine timestamp with permission bits
    timestamp = Time.now.to_f.floor
    permissions = calculate_user_permissions # Returns 0-255
    "#{timestamp}.#{permissions}".to_f
  end
end
```

#### Permission Bit Flags

The system supports 8 permission flags (0-255 range):

| Flag | Value | Permission | Description |
|------|-------|------------|-------------|
| read | 1 | Read access | View document content |
| append | 2 | Append access | Add new content |
| write | 4 | Write access | Modify existing content |
| edit | 8 | Edit access | Full content editing |
| configure | 16 | Configure access | Change document settings |
| delete | 32 | Delete access | Remove document |
| transfer | 64 | Transfer access | Change ownership |
| admin | 128 | Admin access | Full administrative control |

#### Predefined Permission Roles

```ruby
# Permission combinations for common roles
ROLES = {
  viewer: 1,           # read only
  editor: 1 | 2 | 4,   # read + append + write
  moderator: 15,       # read + append + write + edit
  admin: 255           # all permissions
}

# Usage with score encoding
class DocumentAccess
  include Familia::Features::Relationships::ScoreEncoding

  def grant_access(user_id, role = :viewer)
    permissions = ROLES[role]
    encoded_score = encode_score_with_permissions(permissions)
    Document.authorized_users.add(user_id, encoded_score)
  end

  def check_permission(user_id, permission_flag)
    score = Document.authorized_users.score(user_id)
    return false unless score

    _, permissions = decode_score_with_permissions(score)
    (permissions & permission_flag) != 0
  end
end

# Example usage
access = DocumentAccess.new
access.grant_access('user123', :editor)
access.check_permission('user123', 4)  # => true (write permission)
access.check_permission('user123', 32) # => false (no delete permission)
```

#### Time-Based Queries with Permissions

```ruby
# Range queries combining time and permissions
class DocumentAnalytics
  def users_with_access_since(timestamp, min_permissions = 1)
    min_score = "#{timestamp}.#{min_permissions}".to_f
    Document.authorized_users.range_by_score(min_score, '+inf')
  end

  def admin_users_last_week
    week_ago = (Time.now - 7.days).to_f.floor
    admin_permissions = 128
    min_score = "#{week_ago}.#{admin_permissions}".to_f

    Document.authorized_users.range_by_score(min_score, '+inf')
  end
end
```

## Indexed By Relationships

### Hash-Based Lookups

The `indexed_by` relationship creates O(1) hash-based indexes for field values. The `context` parameter determines index ownership and scope:

```ruby
class User < Familia::Horreum
  feature :relationships

  field :email, :username, :department

  # Global indexes for system-wide unique lookups
  class_indexed_by :email, :email_index
  class_indexed_by :username, :username_index

  # Scoped indexes for values unique within a context
  indexed_by :department, :department_index, parent: Organization
end

# Usage for Global Context
user = User.new(email: 'john@example.com', username: 'johndoe')

# Add to global indexes (instance methods)
user.add_to_global_email_index
user.add_to_global_username_index

# Fast O(1) lookups (class methods)
user_id = User.email_index.get('john@example.com')    # => user.identifier
user_id = User.username_index.get('johndoe')         # => user.identifier

# Batch operations
users = [user1, user2, user3]
users.each { |u| u.add_to_global_email_index }

# Check if indexed
User.email_index.exists?('john@example.com')  # => true

# Usage for Scoped Context
organization = Organization.new(org_id: 'acme_corp')
organization.find_by_department('engineering')        # Find user by department within this org
```

### Context Parameter Usage Patterns

Understanding when to use global vs class context:

```ruby
class Product < Familia::Horreum
  feature :relationships

  field :sku, :category, :brand

  # Global context: SKUs must be unique system-wide
  class_indexed_by :sku, :sku_index

  # Class context: Categories are unique per brand
  indexed_by :category, :category_index, parent: Brand
end

class Brand < Familia::Horreum
  feature :relationships

  identifier_field :brand_id
  field :brand_id, :name
  sorted_set :products
end

# Usage patterns:
product = Product.new(sku: 'ELEC001', category: 'laptops', brand: 'apple')

# Global indexing (system-wide unique SKUs)
product.add_to_global_sku_index
Product.sku_index.get('ELEC001')  # => product.identifier

# Scoped indexing (categories unique per brand)
brand = Brand.new(brand_id: 'apple', name: 'Apple Inc.')
brand.find_by_category('laptops')         # Find products in this brand's laptop category
```

### Context Parameter Reference

The `context` parameter is a **required** architectural decision that determines index scope:

| Context Type | Usage | Redis Key Pattern | When to Use |
|--------------|--------|------------------|-------------|
| `:global` | `context: :global` | `global:index_name` | Field values unique system-wide (emails, usernames, API keys) |
| Class | `context: SomeClass` | `someclass:123:index_name` | Field values unique within parent object scope (project names per team) |

#### Generated Methods

**Global Context** (`context: :global`):
- **Instance methods**: `object.add_to_global_index_name`, `object.remove_from_global_index_name`
- **Class methods**: `Class.index_name` (returns hash), `Class.find_by_field`

**Class Context** (`context: Customer`):
- **Instance methods**: `object.add_to_customer_index_name(customer)`, `object.remove_from_customer_index_name(customer)`
- **Class methods on context**: `customer.find_by_field(value)`, `customer.find_all_by_field(values)`

#### Migration from Incorrect Syntax

```ruby
# ❌ Old incorrect syntax (will cause ArgumentError)
indexed_by :email_lookup, field: :email

# ✅ New correct syntax
class_indexed_by :email, :email_lookup                  # Global scope
indexed_by :email, :customer_lookup, parent: Customer   # Scoped per customer
```

## Member Of Relationships

### Bidirectional Membership

The `member_of` relationship creates bidirectional associations with collision-free method naming:

```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid, :name

  # Collections for owned objects
  set :domains
  list :projects
  set :users
end

class Domain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id, :name

  # Declare membership in customer collections
  member_of Customer, :domains, type: :set
end

class Project < Familia::Horreum
  feature :relationships

  identifier_field :project_id
  field :project_id, :name

  member_of Customer, :projects, type: :list
end

class User < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id, :email

  member_of Customer, :users, type: :set
end
```

### Collision-Free Method Generation

The system automatically generates collision-free methods when multiple classes have the same collection name:

```ruby
class Team < Familia::Horreum
  feature :relationships
  set :users  # Same collection name as Customer
end

class User < Familia::Horreum
  feature :relationships

  # Both memberships create unique methods
  member_of Customer, :users, type: :set
  member_of Team, :users, type: :set
end

# Generated methods are collision-free:
user = User.new(user_id: 'user123')

# Add to different collections
user.add_to_customer_users(customer.custid)  # Specific to Customer.users
user.add_to_team_users(team.team_id)         # Specific to Team.users

# Check membership
user.in_customer_users?(customer.custid)     # => true
user.in_team_users?(team.team_id)            # => true

# Remove from specific collections
user.remove_from_customer_users(customer.custid)
user.remove_from_team_users(team.team_id)
```

### Multi-Context Membership Patterns

```ruby
class Document < Familia::Horreum
  feature :relationships

  identifier_field :doc_id
  field :doc_id, :title

  # Multiple membership contexts
  member_of Customer, :documents, type: :set
  member_of Project, :documents, type: :list
  member_of Team, :shared_docs, type: :sorted_set
end

# Usage - same document can belong to multiple contexts
doc = Document.new(doc_id: 'doc123', title: 'Requirements')

# Add to different organizational contexts
doc.add_to_customer_documents(customer.custid)
doc.add_to_project_documents(project.project_id)
doc.add_to_team_shared_docs(team.team_id, score: Time.now.to_i)

# Query membership across contexts
doc.in_customer_documents?(customer.custid)     # => true
doc.in_project_documents?(project.project_id)   # => true
doc.in_team_shared_docs?(team.team_id)          # => true
```

## Advanced Features

### Atomic Multi-Collection Operations

```ruby
class BusinessLogic
  def transfer_domain(domain, from_customer, to_customer)
    # Atomic transfer across multiple collections
    Familia.transaction do |conn|
      # Remove from old customer
      domain.remove_from_customer_domains(from_customer.custid)
      from_customer.domains.remove(domain.identifier)

      # Add to new customer
      domain.add_to_customer_domains(to_customer.custid)
      to_customer.domains.add(domain.identifier)
    end
  end

  def bulk_permission_update(user_ids, new_permissions)
    Document.authorized_users.pipeline do |pipe|
      user_ids.each do |user_id|
        current_score = Document.authorized_users.score(user_id)
        if current_score
          timestamp = current_score.floor
          new_score = "#{timestamp}.#{new_permissions}".to_f
          pipe.zadd(Document.authorized_users.key, new_score, user_id)
        end
      end
    end
  end
end
```

### Performance Optimizations

```ruby
class OptimizedQueries
  # Batch membership checks
  def check_multiple_memberships(user_ids, customer)
    # Single Redis call instead of multiple
    Customer.users.pipeline do |pipe|
      user_ids.each { |uid| pipe.sismember(customer.users.key, uid) }
    end
  end

  # Efficient range queries with permissions
  def recent_editors_with_write_access(hours = 24)
    since = (Time.now - hours.hours).to_f.floor
    write_permission = 4
    min_score = "#{since}.#{write_permission}".to_f

    Document.authorized_users.range_by_score(min_score, '+inf')
  end

  # Batch index updates
  def reindex_users(users)
    User.email_index.pipeline do |pipe|
      users.each do |user|
        pipe.hset(User.email_index.key, user.email, user.identifier)
      end
    end
  end
end
```

## Integration Patterns

### Multi-Tenant Applications

```ruby
class Organization < Familia::Horreum
  feature :relationships

  identifier_field :org_id
  field :org_id, :name, :plan

  # Organization collections
  set :members
  set :projects
  sorted_set :activity_feed
end

class User < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id, :email, :role

  # Multi-tenant membership
  member_of Organization, :members, type: :set
  class_tracked_in :global_activity, score: :created_at
  class_indexed_by :email, :email_lookup
end

class Project < Familia::Horreum
  feature :relationships

  identifier_field :project_id
  field :project_id, :name, :status

  member_of Organization, :projects, type: :set
  class_tracked_in :status_timeline,
    score: ->(proj) { "#{Time.now.to_i}.#{proj.status.hash}" }
end

# Usage
org = Organization.new(org_id: 'org123', name: 'Acme Corp')
user = User.new(user_id: 'user456', email: 'john@acme.com')
project = Project.new(project_id: 'proj789', name: 'Website')

# Establish relationships
user.add_to_organization_members(org.org_id)
project.add_to_organization_projects(org.org_id)

# Query organization structure
org.members.size      # Number of organization members
org.projects.members  # All project IDs in organization

# Global indexes
User.add_to_email_lookup(user)
user_id = User.email_lookup.get('john@acme.com')  # Fast email lookup
```

### Analytics and Reporting

```ruby
class AnalyticsService
  def user_engagement_report(days = 30)
    since = (Time.now - days.days).to_f.floor

    # Get all users active in time period
    active_users = User.activity.range_by_score(since, '+inf')

    # Analyze permission levels
    permission_breakdown = Document.authorized_users
      .range_by_score(since, '+inf', with_scores: true)
      .group_by { |user_id, score| decode_permissions(score) }

    {
      total_active_users: active_users.size,
      permission_breakdown: permission_breakdown.transform_values(&:size),
      top_contributors: User.activity.range(0, 9, with_scores: true)
    }
  end

  def project_status_timeline(project_id)
    project = Project.find(project_id)
    Project.status_timeline
      .range_by_score('-inf', '+inf', with_scores: true)
      .select { |id, _| id == project_id }
      .map { |_, score| decode_status_change(score) }
  end

  private

  def decode_permissions(score)
    _, permissions = score.to_s.split('.').map(&:to_i)
    case permissions
    when 1 then :viewer
    when 15 then :moderator
    when 255 then :admin
    else :custom
    end
  end

  def decode_status_change(score)
    timestamp, status_hash = score.to_s.split('.').map(&:to_i)
    {
      timestamp: Time.at(timestamp),
      status: reverse_status_hash(status_hash)
    }
  end
end
```

## Testing Relationships

### RSpec Testing Patterns

```ruby
RSpec.describe "Relationships Feature" do
  let(:customer) { Customer.new(custid: 'cust123', name: 'Acme Corp') }
  let(:domain) { Domain.new(domain_id: 'dom456', name: 'acme.com') }
  let(:user) { User.new(user_id: 'user789', email: 'john@acme.com') }

  describe "tracked_in relationships" do
    it "tracks objects with score encoding" do
      User.add_to_leaderboard(user)
      score = User.leaderboard.score(user.identifier)

      expect(score).to be_a(Float)
      expect(User.leaderboard.rank(user.identifier)).to be >= 0
    end

    it "supports permission bit encoding" do
      # Test permission encoding
      encoded = encode_score_with_permissions(15) # moderator permissions
      timestamp, permissions = decode_score_with_permissions(encoded)

      expect(permissions).to eq(15)
      expect(timestamp).to be_within(1).of(Time.now.to_i)
    end
  end

  describe "indexed_by relationships" do
    it "creates O(1) hash lookups" do
      User.add_to_email_lookup(user)
      found_id = User.email_lookup.get(user.email)

      expect(found_id).to eq(user.identifier)
    end

    it "handles batch operations" do
      users = [user, user2, user3]
      users.each { |u| User.add_to_email_lookup(u) }

      users.each do |u|
        expect(User.email_lookup.get(u.email)).to eq(u.identifier)
      end
    end
  end

  describe "member_of relationships" do
    it "creates bidirectional associations" do
      domain.add_to_customer_domains(customer.custid)
      customer.domains.add(domain.identifier)

      expect(domain.in_customer_domains?(customer.custid)).to be true
      expect(customer.domains.member?(domain.identifier)).to be true
    end

    it "generates collision-free methods" do
      expect(domain).to respond_to(:add_to_customer_domains)
      expect(domain).to respond_to(:in_customer_domains?)
      expect(domain).to respond_to(:remove_from_customer_domains)
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe "Relationships Integration" do
  scenario "multi-tenant organization with full relationship graph" do
    # Create organization structure
    org = Organization.create(org_id: 'org123', name: 'Tech Corp')

    # Create users with different roles
    admin = User.create(user_id: 'admin1', email: 'admin@tech.com', role: 'admin')
    dev = User.create(user_id: 'dev1', email: 'dev@tech.com', role: 'developer')

    # Create projects
    project = Project.create(project_id: 'proj1', name: 'Web App')

    # Establish all relationships
    admin.add_to_organization_members(org.org_id)
    dev.add_to_organization_members(org.org_id)
    project.add_to_organization_projects(org.org_id)

    # Add to indexes
    User.add_to_email_lookup(admin)
    User.add_to_email_lookup(dev)

    # Test relationship integrity
    expect(org.members.size).to eq(2)
    expect(org.projects.size).to eq(1)

    # Test lookups
    expect(User.email_lookup.get('admin@tech.com')).to eq(admin.identifier)
    expect(User.email_lookup.get('dev@tech.com')).to eq(dev.identifier)

    # Test membership queries
    expect(admin.in_organization_members?(org.org_id)).to be true
    expect(project.in_organization_projects?(org.org_id)).to be true
  end
end
```

## Best Practices

### Relationship Design

1. **Choose the Right Type**:
   - Use `tracked_in` for activity feeds, leaderboards, time-series data
   - Use `indexed_by` for fast lookups by field values
   - Use `member_of` for bidirectional ownership/membership

2. **Score Encoding Strategy**:
   - Combine timestamps with metadata for rich queries
   - Use bit flags for permissions (supports 8 flags efficiently)
   - Consider sort order requirements when designing scores

3. **Performance Optimization**:
   - Batch operations when possible using pipelines
   - Use appropriate Redis data types for your access patterns
   - Index only frequently-queried fields

### Memory and Storage

1. **Efficient Bit Encoding**:
   - 8 bits can encode 256 permission combinations
   - Single Redis sorted set score contains time + permissions
   - Reduces memory vs. separate permission records

2. **Key Design**:
   - Relationship keys follow pattern: `class:field:collection`
   - Collision-free method names prevent namespace conflicts
   - Predictable key structure aids debugging

3. **Cleanup Strategies**:
   - Remove objects from all relationship collections on deletion
   - Use TTL on temporary relationship data
   - Regular cleanup of stale indexes

### Security Considerations

1. **Permission Validation**:
   - Always validate permissions before operations
   - Use bit flags for efficient permission checking
   - Audit permission changes with timestamps

2. **Access Control**:
   - Verify relationship membership before granting access
   - Use consistent permission models across features
   - Log relationship changes for audit trails

The Relationships feature provides a comprehensive foundation for building sophisticated multi-tenant applications with efficient object relationships, permission management, and analytics capabilities.
