# Relationships Feature Guide

The Relationships feature transforms how you manage object associations in Familia applications. Instead of manually maintaining foreign keys and indexes, relationships provide automatic bidirectional links, efficient queries, and Ruby-like collection syntax that makes working with related objects feel natural and intuitive.

> [!TIP]
> Enable relationships with `feature :relationships`, define associations with `relates_to`, and use clean Ruby syntax like `customer.domains << domain` to manage relationships.

## Understanding Object Relationships

### The Challenge of Manual Associations

Without relationships, connecting objects requires manual index management:

```ruby
# Manual approach - error-prone and verbose
class Customer < Familia::Horreum
  field :name, :email
  set :domain_ids  # Manually track related domain IDs
end

class Domain < Familia::Horreum
  field :name, :customer_id  # Manually track owning customer
end

# Manual relationship management
customer = Customer.new(name: "Acme Corp")
domain = Domain.new(name: "acme.com", customer_id: customer.identifier)

# Add to customer's domain list
customer.domain_ids.add(domain.identifier)
customer.save

# Both objects must be updated manually - easy to get out of sync!
```

### The Relationships Solution

The relationships feature automates bidirectional associations and provides Ruby-like syntax:

```ruby
# Relationships approach - clean and automatic
class Customer < Familia::Horreum
  feature :relationships

  field :name, :email
  set :domains  # Collection for related objects
end

class Domain < Familia::Horreum
  feature :relationships

  field :name
  relates_to Customer, via: :domains  # Automatic bidirectional link
end

# Clean, Ruby-like relationship management
customer = Customer.new(name: "Acme Corp")
domain = Domain.new(name: "acme.com")

customer.domains << domain  # Automatic bidirectional update!
# Now: domain.in_customer_domains?(customer.identifier) => true
#  And: customer.domains.member?(domain.identifier) => true
```

> [!NOTE]
> **Key Benefits:**
> - **Automatic Management**: Relationships stay synchronized without manual intervention
> - **Ruby-like Syntax**: Use familiar collection operators like `<<` and `delete`
> - **Bidirectional Links**: Changes update both sides of the relationship automatically
> - **Efficient Queries**: O(1) lookups with automatic index maintenance

## Core Relationship Patterns

### Basic Bidirectional Relationships

The most common pattern connects two object types with automatic bidirectional updates:

```ruby
class User < Familia::Horreum
  feature :relationships

  identifier_field :email
  field :email, :name
  set :teams  # Collection to hold team relationships
end

class Team < Familia::Horreum
  feature :relationships

  identifier_field :name
  field :name, :description
  relates_to User, via: :teams  # Define the relationship
end

# Usage examples
alice = User.create(email: "alice@company.com", name: "Alice")
dev_team = Team.create(name: "developers", description: "Development Team")

# Add relationship - updates both objects automatically
alice.teams << dev_team

# Query from either side
alice.teams.member?(dev_team.identifier)     # => true
dev_team.in_user_teams?(alice.identifier)    # => true

# Remove relationship
alice.teams.delete(dev_team.identifier)
dev_team.in_user_teams?(alice.identifier)    # => false
```

> [!IMPORTANT]
> The object that holds the collection (like `set :teams` in User) must define the collection field. The related object uses `relates_to` to reference that collection.

### Many-to-Many Relationships

Handle complex many-to-many scenarios where objects can belong to multiple collections:

```ruby
class Project < Familia::Horreum
  feature :relationships

  field :name, :status
  set :contributors     # Project can have many contributors
  set :reviewers        # Project can have many reviewers
end

class Developer < Familia::Horreum
  feature :relationships

  field :name, :role
  relates_to Project, via: :contributors  # Can contribute to many projects
  relates_to Project, via: :reviewers     # Can review many projects
end

# Usage
project = Project.create(name: "Web App", status: "active")
alice = Developer.create(name: "Alice", role: "frontend")
bob = Developer.create(name: "Bob", role: "backend")

# Alice contributes, Bob reviews
project.contributors << alice
project.reviewers << bob

# Check relationships
alice.in_project_contributors?(project.identifier)  # => true
bob.in_project_reviewers?(project.identifier)       # => true
bob.in_project_contributors?(project.identifier)    # => false
```

> [!TIP]
> Method names follow the pattern `in_{parent}_{collection}?` for checking membership, making relationship queries self-documenting.

## Automatic Index Management

### Class-Level Tracking

The relationships feature can automatically track objects at the class level for efficient querying:

```ruby
class User < Familia::Horreum
  feature :relationships

  field :email, :created_at, :department

  # Automatic class-level tracking
  class_indexed_by :email, :email_lookup          # O(1) email lookups
  class_participates_in :all_users, score: :created_at  # Chronological tracking
end

# Automatic index updates on save/destroy
user = User.create(email: "alice@company.com", created_at: Time.now.to_i)

# O(1) lookup by email (automatically maintained)
found_id = User.email_lookup.get("alice@company.com")
found_user = User.find_by_email("alice@company.com")  # Convenience method

# Time-based queries (automatically maintained)
recent_users = User.all_users.range_by_score(
  (Time.now - 24.hours).to_i, '+inf'
)
```

### Relationship-Scoped Indexing

Create indexes that scope to specific relationships:

```ruby
class Customer < Familia::Horreum
  feature :relationships

  field :name, :tier
  set :domains
end

class Domain < Familia::Horreum
  feature :relationships

  field :name, :status
  relates_to Customer, via: :domains

  # Index domains by name within each customer
  indexed_by :name, :domain_index, parent: Customer
end

# Usage
customer = Customer.create(name: "Acme Corp")
domain = Domain.create(name: "acme.com", status: "active")
customer.domains << domain

# Scoped lookup: find domain by name within specific customer
found_domain = customer.find_by_name("acme.com")
```

> [!NOTE]
> Relationship-scoped indexes provide O(1) lookups within the context of a specific parent object, perfect for scenarios like "find user's domain by name" rather than global searches.

## Ruby-like Collection Operations

### Adding and Removing Objects

The relationships feature provides intuitive collection syntax:

```ruby
class Organization < Familia::Horreum
  feature :relationships
  field :name
  set :members, :teams
end

class Person < Familia::Horreum
  feature :relationships
  field :name, :role
  relates_to Organization, via: :members
end

org = Organization.create(name: "Tech Corp")
alice = Person.create(name: "Alice", role: "developer")
bob = Person.create(name: "Bob", role: "designer")

# Single additions
org.members << alice                    # Add one member
org.members.add(bob.identifier)         # Alternative syntax

# Bulk operations
org.members.merge([alice.identifier, bob.identifier])  # Add multiple
org.members.clear                       # Remove all members

# Checking membership
org.members.member?(alice.identifier)   # => true
org.members.include?(bob.identifier)    # => true (alias)
org.members.size                        # => 2
```

### Collection Queries and Iteration

Work with relationship collections like standard Ruby collections:

```ruby
# Get all member identifiers
member_ids = org.members.to_a

# Load actual objects (requires separate queries)
members = member_ids.map { |id| Person.load(id) }.compact

# Count relationships
total_members = org.members.size

# Check for empty relationships
has_members = !org.members.empty?

# Set operations
common_members = org1.members & org2.members  # Intersection
all_members = org1.members | org2.members     # Union
unique_to_org1 = org1.members - org2.members  # Difference
```

> [!WARNING]
> Relationship collections store identifiers, not full objects. Load related objects only when needed to maintain performance with large datasets.

## Time-Based and Scored Relationships

### Chronological Tracking

Track when relationships were established using scored collections:

```ruby
class Timeline < Familia::Horreum
  feature :relationships

  field :user_id
  sorted_set :events  # Scored by timestamp
end

class Event < Familia::Horreum
  feature :relationships

  field :type, :data, :timestamp
  relates_to Timeline, via: :events, score: :timestamp
end

# Usage
timeline = Timeline.create(user_id: "user123")
event = Event.create(
  type: "login",
  data: "successful",
  timestamp: Time.now.to_i
)

# Add with automatic scoring
timeline.events << event  # Uses event.timestamp as score

# Time-based queries
recent_events = timeline.events.range_by_score(
  (Time.now - 1.hour).to_i, '+inf'
)

# Get events in chronological order
all_events = timeline.events.range(0, -1, with_scores: true)
```

### Priority and Ranking Systems

Use custom scoring for priority-based relationships:

```ruby
class Project < Familia::Horreum
  feature :relationships

  field :name
  sorted_set :tasks  # Scored by priority
end

class Task < Familia::Horreum
  feature :relationships

  field :title, :priority, :status
  relates_to Project, via: :tasks, score: :priority
end

# Usage
project = Project.create(name: "Website Redesign")
urgent_task = Task.create(title: "Fix login bug", priority: 10, status: "open")
normal_task = Task.create(title: "Update copy", priority: 5, status: "open")

project.tasks << urgent_task
project.tasks << normal_task

# Get highest priority tasks first
high_priority = project.tasks.range(0, 4, order: 'DESC')  # Top 5 tasks
task_rank = project.tasks.rank(urgent_task.identifier, order: 'DESC')  # => 0 (highest)
```

> [!NOTE]
> **Scoring Strategies:** Common scoring patterns include timestamps (chronological), priority levels (ranking), user ratings, or composite scores combining multiple factors.

## Advanced Relationship Patterns

### Conditional Relationships

Use lambda scoring for dynamic relationship management:

```ruby
class User < Familia::Horreum
  feature :relationships

  field :name, :status, :last_active
  class_participates_in :active_users,
    score: ->(user) { user.status == 'active' ? user.last_active : 0 }
end

# Only active users get meaningful scores
user = User.create(name: "Alice", status: "active", last_active: Time.now.to_i)
inactive_user = User.create(name: "Bob", status: "inactive", last_active: Time.now.to_i)

# Alice gets normal score, Bob gets 0 (filtered out in most queries)
User.active_users.range_by_score(1, '+inf')  # Only returns Alice
```

### Relationship Cleanup and Maintenance

Handle object lifecycle with automatic relationship cleanup:

```ruby
class Customer < Familia::Horreum
  feature :relationships

  field :name, :status
  set :domains

  # Override destroy to handle relationship cleanup
  def destroy
    # Remove from all domains before destroying
    domains.to_a.each do |domain_id|
      if domain = Domain.load(domain_id)
        domains.delete(domain_id)  # Clean bidirectional link
      end
    end
    super
  end
end

# When customer is destroyed, all domain relationships are cleaned up
customer.destroy  # Automatically maintains data integrity
```

> [!IMPORTANT]
> Always consider relationship cleanup when objects are destroyed. The relationships feature handles most cases automatically, but complex scenarios may need custom cleanup logic.

## Common Patterns and Best Practices

### Efficient Bulk Operations

Handle large datasets efficiently with bulk relationship operations:

```ruby
# Adding many relationships at once
customer = Customer.load("customer123")
domain_ids = %w[domain1 domain2 domain3 domain4 domain5]

# Efficient bulk addition
customer.domains.merge(domain_ids)

# Instead of multiple individual additions (slower)
domain_ids.each { |id| customer.domains << id }  # Avoid this pattern
```

### Relationship Validation

Add validation to ensure relationship integrity:

```ruby
class Team < Familia::Horreum
  feature :relationships

  field :name, :max_members
  set :members

  def add_member(user_id)
    if members.size >= max_members
      raise "Team is full (max #{max_members} members)"
    end

    members << user_id
  end

  def can_add_member?
    members.size < max_members
  end
end
```

### Querying Related Data

Efficient patterns for loading related objects:

```ruby
# Get customer's domain names efficiently
customer = Customer.load("customer123")
domain_ids = customer.domains.to_a

# Batch load domains (more efficient than individual loads)
domains = Domain.multiget(*domain_ids)

# Extract specific fields without loading full objects
domain_names = domain_ids.map do |id|
  Domain.new(domain_id: id).name  # Load just the name field
end
```

> [!TIP]
> **Performance Tips:**
> - Use `multiget` for loading multiple related objects
> - Load only needed fields when possible
> - Consider caching frequently accessed relationship data
> - Use bulk operations for multiple relationship changes

## Troubleshooting Relationships

### Common Issues and Solutions

**Issue: Relationships not updating bidirectionally**
```ruby
# Problem: Only updating one side
customer.domains.add(domain.identifier)  # Domain doesn't know about customer

# Solution: Use proper relationship syntax
customer.domains << domain  # Automatically updates both sides
```

**Issue: Stale relationship data**
```ruby
# Problem: Deleted objects still in relationships
customer.domains.to_a.include?("deleted_domain")  # => true

# Solution: Clean up relationships when objects are destroyed
def destroy
  # Remove from all relationships before destroying
  cleanup_relationships
  super
end
```

**Issue: Performance problems with large relationship sets**
```ruby
# Problem: Loading all relationships unnecessarily
all_domains = customer.domains.to_a.map { |id| Domain.load(id) }

# Solution: Use pagination and selective loading
recent_domains = customer.domains.range(0, 9)  # First 10 only
domain_count = customer.domains.size  # Count without loading
```

### Debugging Relationship State

Tools for understanding relationship data:

```ruby
# Check relationship status
customer.domains.size                    # Count of relationships
customer.domains.empty?                  # Any relationships exist?
customer.domains.to_a                    # All relationship IDs

# Verify bidirectional consistency
domain_id = customer.domains.to_a.first
domain = Domain.load(domain_id)
domain.in_customer_domains?(customer.identifier)  # Should be true

# Debug relationship indexes
Customer.email_lookup.to_h               # All email->ID mappings
User.all_users.range(0, -1, with_scores: true)  # All users with scores
```

---

## See Also

- **[Technical Reference](../reference/api-technical.md#relationships-feature-v200-pre7)** - Implementation details and advanced patterns
- **[Relationship Methods Guide](feature-relationships-methods.md)** - Complete method reference
- **[Feature System Guide](feature-system.md)** - Understanding Familia's feature architecture
- **[Implementation Guide](implementation.md)** - Production deployment and configuration patterns

> [!NOTE]
> **Next Steps:** Once you're comfortable with basic relationships, explore the [Relationship Methods Guide](feature-relationships-methods.md) for detailed method references, or check the [Technical Reference](../reference/api-technical.md#relationships-feature-v200-pre7) for advanced patterns like permission encoding and performance optimization.
