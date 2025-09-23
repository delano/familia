# Relationships Feature Guide

The Relationships feature transforms how you manage object associations in Familia applications. Instead of manually maintaining foreign keys and indexes, relationships provide automatic bidirectional links, efficient queries, and Ruby-like collection syntax that makes working with related objects feel natural and intuitive.

This guide provides a breadth-first introduction to the four core relationship capabilities: **participation**, **indexing**, **querying**, and **cascading operations**.

> [!TIP]
> Enable relationships with `feature :relationships`, define associations with `participates_in`, and use clean Ruby syntax like `customer.domains << domain` to manage relationships.

## What Are Relationships?

Relationships automate object associations in Familia, eliminating manual foreign key management:

```ruby
# Without relationships - manual and error-prone
customer.domain_ids.add(domain.identifier)
domain.customer_id = customer.identifier

# With relationships - automatic and clean
customer.domains << domain  # Updates both sides automatically
```

**Key Benefits:**
- **Automatic bidirectional updates** - no manual synchronization
- **Ruby-like syntax** - familiar `<<` and collection operations
- **O(1) lookups** - efficient Redis-backed indexing
- **Lifecycle management** - automatic cleanup and maintenance

## Core Relationship Capabilities

### 1. Participation - Bidirectional Object Links

Connect objects with automatic synchronization:

```ruby
class User < Familia::Horreum
  feature :relationships
  set :teams  # Collection holder
end

class Team < Familia::Horreum
  feature :relationships
  participates_in User, :teams  # Declares participation
end

# Usage - automatic bidirectional updates
user.teams << team
team.in_user_teams?(user)  # => true
```

**Many-to-Many Example:**
```ruby
class Project < Familia::Horreum
  set :contributors, :reviewers
end

class Developer < Familia::Horreum
  participates_in Project, :contributors
  participates_in Project, :reviewers
end

project.contributors << alice  # Alice contributes
project.reviewers << bob       # Bob reviews
```

### 2. Indexing - Automatic Object Tracking

Enable O(1) lookups with automatic index management:

```ruby
class User < Familia::Horreum
  feature :relationships
  field :email, :created_at

  # Global unique lookups
  class_indexed_by :email, :email_lookup

  # Scored tracking collections
  class_participates_in :all_users, score: :created_at
end

# Automatic on save/destroy
User.find_by_email("alice@example.com")    # O(1) lookup
User.all_users.range(0, 9)                 # Most recent 10 users
```

**Relationship-Scoped Indexing:**
```ruby
class Domain < Familia::Horreum
  participates_in Customer, :domains
  indexed_by :name, :domain_index, target: Customer  # Unique per customer
end

customer.find_by_name("example.com")  # Find domain within this customer
```

### 3. Querying - Ruby-like Collection Operations

Work with relationships like standard Ruby collections:

```ruby
# Standard collection operations
org.members << alice                    # Add relationship
org.members.merge([id1, id2, id3])     # Bulk additions
org.members.size                       # Count relationships
org.members.empty?                     # Check if any exist

# Set operations
common = org1.members & org2.members   # Intersection
all = org1.members | org2.members      # Union

# Load actual objects when needed
member_ids = org.members.to_a
members = Person.multiget(*member_ids)  # Efficient bulk loading
```

> [!WARNING]
> Collections store identifiers, not objects. Use `multiget` for efficient bulk loading.

### 4. Cascading Operations - Scored Relationships

Use scores for time-based tracking and priority systems:

```ruby
class Timeline < Familia::Horreum
  feature :relationships
  sorted_set :events  # Scored collection
end

class Event < Familia::Horreum
  feature :relationships
  field :timestamp, :priority
  participates_in Timeline, :events, score: :timestamp
end

# Automatic scoring when relationships established
timeline.events << event  # Uses event.timestamp as score

# Time-based and priority queries
recent = timeline.events.range_by_score((Time.now - 1.hour).to_i, '+inf')
top_priority = project.tasks.range(0, 4, order: 'DESC')  # Highest priority first
```

**Common Scoring Patterns:**
- **Timestamps** for chronological ordering
- **Priority levels** for ranking systems
- **User ratings** for recommendation systems
- **Custom lambdas** for complex scoring logic

## Best Practices

**Performance:**
- Use `merge([id1, id2, id3])` for bulk additions
- Use `multiget(*ids)` for efficient bulk loading
- Use pagination: `collection.range(0, 9)` instead of loading all

**Lifecycle Management:**
```ruby
def destroy
  cleanup_relationships  # Remove from all relationships first
  super
end
```

**Validation:**
```ruby
def add_member(user_id)
  raise "Team is full" if members.size >= max_members
  members << user_id
end
```

## Common Patterns

**Conditional Scoring:**
```ruby
class_participates_in :active_users,
  score: ->(user) { user.active? ? user.last_activity : 0 }
```

**Bidirectional Updates:**
```ruby
# ✅ Automatic bidirectional
customer.domains << domain

# ❌ Manual (avoid)
customer.domains.add(domain.identifier)
```

---

## See Also

- **[Technical Reference](../reference/api-technical.md#relationships-feature-v200-pre7)** - Implementation details and advanced patterns
- **[Relationship Methods Guide](feature-relationships-methods.md)** - Complete method reference
- **[Feature System Guide](feature-system.md)** - Understanding Familia's feature architecture
- **[Implementation Guide](implementation.md)** - Production deployment and configuration patterns

> [!NOTE]
> **Next Steps:** Once you're comfortable with basic relationships, explore the [Relationship Methods Guide](feature-relationships-methods.md) for detailed method references, or check the [Technical Reference](../reference/api-technical.md#relationships-feature-v200-pre7) for advanced patterns like permission encoding and performance optimization.
