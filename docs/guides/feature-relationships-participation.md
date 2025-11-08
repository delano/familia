# Relationships Participation Guide

Participation creates bidirectional associations between Familia objects with automatic reverse tracking, semantic scoring, and lifecycle management.

## Core Concepts

Participation manages "belongs to" relationships where:
- **Membership has meaning** - Customer owns Domains, User belongs to Teams
- **Scores have semantic value** - Priority, timestamps, permissions
- **Bidirectional tracking** - Both sides know about the relationship
- **Lifecycle matters** - Automatic cleanup on destroy

## Basic Usage

```ruby
class Domain < Familia::Horreum
  feature :relationships
  field :created_at

  participates_in Customer, :domains, score: :created_at
end

class Customer < Familia::Horreum
  feature :relationships
  # sorted_set :domains created automatically
end

# Bidirectional relationship management
customer.add_domains_instance(domain)     # Add with timestamp score
domain.in_customer_domains?(customer)     # => true
domain.customer_instances                 # => [customer]
```

## Collection Types

### Sorted Set (Default)

Ordered collections with semantic scores:

```ruby
participates_in Project, :tasks, score: :priority

project.tasks.range(0, 4, order: 'DESC')  # Top 5 by priority
task.score_in_project_tasks(project)      # Get current score
```

### Unsorted Set

Simple membership without ordering:

```ruby
participates_in Team, :members, type: :set

team.members.member?(user.identifier)     # Fast O(1) check
```

### List

Ordered sequences:

```ruby
participates_in Playlist, :songs, type: :list

song.position_in_playlist_songs(playlist)  # Get position
```

## Scoring Strategies

### Field-Based

```ruby
participates_in Category, :articles, score: :published_at
participates_in User, :bookmarks, score: :rating
```

### Lambda-Based

```ruby
participates_in Department, :employees, score: -> {
  performance_rating * 100 + tenure_years * 10
}
```

### Permission Encoding

```ruby
participates_in Customer, :domains, score: -> {
  permission_encode(created_at, permission_bits)
}

customer.domains_with_permission(:read)  # Query by permission
```

## Class-Level Participation

Track all instances automatically:

```ruby
class User < Familia::Horreum
  class_participates_in :all_users, score: :created_at
  class_participates_in :active_users,
    score: ->(u) { u.active? ? u.last_activity : 0 }
end

User.all_users.size                # Total count
User.active_users.range(0, 9)      # Top 10 active
```

## Multiple Collections

Participants can belong to multiple collections:

```ruby
class User < Familia::Horreum
  participates_in Team, :members
  participates_in Team, :admins
  participates_in Organization, :employees, as: :employers
end

# Separate methods per collection
user.add_to_team_members(team)
user.add_to_team_admins(team)

# Reverse methods union collections
user.team_instances      # Union of members + admins
user.employers_instances  # Custom name via 'as:'
```

## Lifecycle Management

### Automatic Tracking

Familia maintains a reverse index for cleanup:

```ruby
domain.participations.members
# => ["customer:cust_123:domains", "customer:cust_456:domains"]

domain.current_participations
# => [
#   { collection_key: "customer:cust_123:domains", score: 1640995200 },
#   { collection_key: "customer:cust_456:domains", score: 1640995300 }
# ]
```

### Cleanup

```ruby
class Domain < Familia::Horreum
  before_destroy :cleanup_relationships

  def cleanup_relationships
    # Automatic removal from all collections
    super
  end
end
```

## Advanced Patterns

### Conditional Scoring

```ruby
participates_in Project, :tasks, score: -> {
  status == 'active' ? priority : 0
}

# Filter by score
active_tasks = project.tasks.range_by_score(1, '+inf')
```

### Time-Based Expiration

```ruby
participates_in User, :sessions, score: :expires_at

# Query active sessions
now = Time.now.to_i
active = user.sessions.range_by_score(now, '+inf')
```

### Validation

```ruby
def add_members_instance(user, score = nil)
  raise "Team is full" if members.size >= max_members
  raise "User not active" unless user.status == 'active'
  super
end
```

## Performance Best Practices

### Bulk Operations

```ruby
# ✅ Efficient bulk add
customer.add_domains([domain1, domain2, domain3])

# ❌ Avoid loops
domains.each { |d| customer.add_domains_instance(d) }
```

### Pagination

```ruby
# ✅ Paginated access
customer.domains.range(0, 19)      # First 20
customer.domains.range(20, 39)     # Next 20

# ❌ Loading all
customer.domains.to_a               # Loads all IDs
```

### Direct Collection Access

```ruby
# For IDs only
customer.domains.to_a               # Just IDs
customer.domains.merge([id1, id2])  # Bulk ID operations

# For objects
domain.customer_instances           # Efficient bulk loading
```

## Troubleshooting

### Common Issues

**Method not found:**
- Ensure `feature :relationships` on both classes
- Verify `participates_in` declaration
- Check method naming patterns

**Inconsistent relationships:**
- Use transactions for complex operations
- Implement validation in overridden methods
- Monitor reverse index consistency

**Performance issues:**
- Use bulk operations
- Implement pagination
- Consider direct collection access for IDs

### Debugging

```ruby
# Check configuration
Domain.participation_relationships
# => [{ target_class: Customer, collection_name: :domains, ... }]

# Inspect participations
domain.current_participations

# Validate consistency
domain.validate_relationships!
```

## See Also

- [**Relationships Overview**](feature-relationships.md) - Core concepts
- [**Methods Reference**](feature-relationships-methods.md) - Complete API
- [**Indexing Guide**](feature-relationships-indexing.md) - Attribute lookups
