# Relationships Feature Guide

The Relationships feature provides automatic bidirectional associations between Familia objects, eliminating manual foreign key management while enabling efficient queries through Redis-native data structures.

> [!TIP]
> Enable with `feature :relationships` and define associations using `participates_in` for automatic method generation.

## Quick Start

```ruby
class Customer < Familia::Horreum
  feature :relationships
  # Collection 'domains' created automatically
end

class Domain < Familia::Horreum
  feature :relationships
  participates_in Customer, :domains
end

# Automatic bidirectional relationship management
customer.add_domains_instance(domain)      # Add relationship
domain.in_customer_domains?(customer)      # => true
domain.customer_instances                  # => [customer]
```

## Core Capabilities

### Participation - Bidirectional Associations

Create semantic relationships between objects with automatic reverse tracking:

```ruby
class User < Familia::Horreum
  feature :relationships
  participates_in Team, :members, score: :joined_at
  participates_in Team, :admins
end

# Generated methods on Team (target)
team.add_members_instance(user)           # Add single member
team.add_members([user1, user2])          # Bulk add
team.members.range(0, 9)                  # First 10 members

# Generated methods on User (participant)
user.add_to_team_members(team)            # Add self to team
user.in_team_admins?(team)                # Check membership
user.team_instances                       # All teams (members + admins)
```

### Indexing - Fast Attribute Lookups

Enable O(1) field-based queries with automatic index management:

```ruby
class User < Familia::Horreum
  feature :relationships
  field :email, :username

  # Global unique indexes (auto-managed on save/destroy)
  unique_index :email, :email_lookup
  unique_index :username, :username_lookup
end

User.find_by_email("alice@example.com")   # O(1) lookup
User.find_by_username("alice")            # O(1) lookup

# Scoped indexing (manual management required)
class Employee < Familia::Horreum
  feature :relationships
  unique_index :badge_number, :badge_index, within: Company
  multi_index :department, :dept_index, within: Company
end

employee.add_to_company_badge_index(company)
company.find_by_badge_number("12345")     # Scoped lookup
company.find_all_by_department("engineering")  # Multi-value
```

### Scoring - Semantic Ordering

Use scores for temporal tracking, priority systems, or custom ordering:

```ruby
class Task < Familia::Horreum
  feature :relationships
  field :priority, :created_at

  # Field-based scoring
  participates_in Project, :tasks, score: :priority

  # Lambda-based scoring
  participates_in Sprint, :tasks, score: -> {
    priority * 100 + (Time.now - created_at) / 3600
  }
end

project.tasks.range(0, 4, order: 'DESC')  # Top 5 by priority
sprint.tasks.range_by_score(500, '+inf')  # High priority tasks
```

## Generated Method Reference

### When Domain declares `participates_in Customer, :domains`

| Class | Method | Purpose |
|-------|--------|---------|
| **Customer** | `domains` | Access collection |
| | `add_domains_instance(domain)` | Add single item |
| | `add_domains([domains])` | Bulk add |
| | `remove_domains_instance(domain)` | Remove item |
| **Domain** | `add_to_customer_domains(customer)` | Add to collection |
| | `remove_from_customer_domains(customer)` | Remove from collection |
| | `in_customer_domains?(customer)` | Check membership |
| | `score_in_customer_domains(customer)` | Get score (sorted_set) |
| | `customer_instances` | Load all customers |
| | `customer_ids` | Get customer IDs |
| | `customer?` | Has any customers? |
| | `customer_count` | Count relationships |

## Common Patterns

### Multiple Collections

```ruby
class User < Familia::Horreum
  feature :relationships
  participates_in Project, :contributors
  participates_in Project, :reviewers
  participates_in Organization, :employees, as: :employers
end

# Separate methods per collection
user.add_to_project_contributors(project)
user.add_to_project_reviewers(project)

# Custom reverse method names
user.employers_instances  # Instead of organization_instances
```

### Class-Level Tracking

```ruby
class Customer < Familia::Horreum
  feature :relationships
  class_participates_in :all_customers, score: :created_at
  class_participates_in :premium_customers,
    score: ->(c) { c.tier == 'premium' ? c.last_activity : 0 }
end

Customer.all_customers.size               # Total count
Customer.premium_customers.range(0, 9)    # Top 10 premium
```

### Performance Optimization

```ruby
# Bulk operations
team.add_members([user1, user2, user3])

# Pagination
team.members.range(0, 19)                 # First 20
team.members.range(20, 39)                # Next 20

# Direct ID access (no object loading)
team.members.to_a                         # Just IDs
team.member_instances                     # Load objects
```

## Best Practices

1. **Use bulk methods** for multiple additions: `add_domains([d1, d2, d3])`
2. **Paginate large collections**: `range(0, 19)` instead of loading all
3. **Leverage reverse methods**: `domain.customer_instances` for efficient loading
4. **Clean up on destroy**: Call `cleanup_relationships` before deletion
5. **Validate before adding**: Check capacity/eligibility in overridden methods

## See Also

- [**Relationship Methods**](feature-relationships-methods.md) - Complete API reference
- [**Participation Guide**](feature-relationships-participation.md) - Deep dive into associations
- [**Indexing Guide**](feature-relationships-indexing.md) - Attribute lookup patterns
