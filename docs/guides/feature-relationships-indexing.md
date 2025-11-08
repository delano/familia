# Relationships Indexing Guide

Indexing provides O(1) field-to-object lookups using Redis data structures, enabling fast attribute-based queries without relationship semantics.

## Core Concepts

Indexing creates fast lookups for finding objects by field values:
- **O(1) performance** - Hash/Set-based constant-time access
- **Automatic management** - Class indexes update on save/destroy
- **Flexible scoping** - Global or parent-scoped uniqueness
- **Query generation** - Automatic `find_by_*` methods

## Index Types

| Type | Scope | Use Case | Structure |
|------|-------|----------|-----------|
| `unique_index` | Class | Global unique fields | Redis HashKey |
| `unique_index` | Instance | Parent-scoped unique | Redis HashKey |
| `multi_index` | Instance | Non-unique groupings | Redis Set |

## Class-Level Unique Indexing

Global unique field lookups with automatic management:

```ruby
class User < Familia::Horreum
  feature :relationships
  field :email, :username

  unique_index :email, :email_lookup
  unique_index :username, :username_lookup
end

# Automatic indexing on save
user = User.create(email: 'alice@example.com')
User.find_by_email('alice@example.com')  # => user (O(1) lookup)

# Automatic update on field change
user.update(email: 'alice.smith@example.com')
User.find_by_email('alice.smith@example.com')  # => user

# Automatic cleanup on destroy
user.destroy
User.find_by_email('alice.smith@example.com')  # => nil
```

### Generated Methods

| Method | Description |
|--------|-------------|
| `User.find_by_email(email)` | O(1) lookup |
| `User.index_email_for(user)` | Manual index |
| `User.unindex_email_for(user)` | Remove from index |
| `User.reindex_email_for(user)` | Update index |

## Instance-Scoped Unique Indexing

Unique within parent context, allowing duplicates across parents:

```ruby
class Employee < Familia::Horreum
  feature :relationships
  field :badge_number

  unique_index :badge_number, :badge_index, within: Company
end

# Manual indexing required (needs parent context)
company1 = Company.create(name: 'Acme Corp')
company2 = Company.create(name: 'Beta Inc')

emp1 = Employee.create(badge_number: '12345')
emp1.add_to_company_badge_index(company1)

emp2 = Employee.create(badge_number: '12345')  # Same badge OK
emp2.add_to_company_badge_index(company2)

# Scoped lookups
company1.find_by_badge_number('12345')  # => emp1
company2.find_by_badge_number('12345')  # => emp2
```

### Generated Methods

**On scope class (Company):**
| Method | Description |
|--------|-------------|
| `find_by_badge_number(badge)` | Find within scope |
| `index_badge_number_for(emp)` | Add to index |
| `unindex_badge_number_for(emp)` | Remove from index |

**On indexed class (Employee):**
| Method | Description |
|--------|-------------|
| `add_to_company_badge_index(company)` | Add to company's index |
| `remove_from_company_badge_index(company)` | Remove from index |
| `in_company_badge_index?(company)` | Check if indexed |

## Multi-Value Indexing

One-to-many mappings for non-unique field values:

```ruby
class Employee < Familia::Horreum
  feature :relationships
  field :department

  multi_index :department, :dept_index, within: Company
end

company = Company.create(name: 'TechCorp')

# Multiple employees in same department
[
  Employee.create(department: 'engineering'),
  Employee.create(department: 'engineering'),
  Employee.create(department: 'sales')
].each { |emp| emp.add_to_company_dept_index(company) }

# Query all in department
engineers = company.find_all_by_department('engineering')  # => [emp1, emp2]
sales_team = company.find_all_by_department('sales')       # => [emp3]

# Random sampling
sample = company.sample_from_department('engineering', 1)  # => [random engineer]
```

### Generated Methods

**On scope class:**
| Method | Description |
|--------|-------------|
| `find_all_by_department(dept)` | Find all in department |
| `sample_from_department(dept, count)` | Random sample |

## Advanced Patterns

### Composite Keys

```ruby
class ApiKey < Familia::Horreum
  field :environment, :key_type

  unique_index :environment_and_type, :env_type_index, within: Customer

  private
  def environment_and_type
    "#{environment}:#{key_type}"  # e.g., "production:read_write"
  end
end

customer.find_by_environment_and_type("production:read_only")
```

### Conditional Indexing

```ruby
class Document < Familia::Horreum
  field :status, :slug

  unique_index :slug, :slug_index, within: Project

  def add_to_project_slug_index(project)
    return unless status == 'published'  # Only index published
    super
  end
end
```

### Time Partitioning

```ruby
class Event < Familia::Horreum
  field :timestamp

  multi_index :daily_partition, :daily_events, within: User

  private
  def daily_partition
    Time.at(timestamp).strftime('%Y%m%d')  # e.g., "20241215"
  end
end

today = Time.now.strftime('%Y%m%d')
todays_events = user.find_all_by_daily_partition(today)
```

## Key Differences

### Class vs Instance Scoping

**Class-level (`unique_index :email, :email_lookup`):**
- Automatic indexing on save/destroy
- System-wide uniqueness
- No parent context needed
- Examples: emails, usernames, API keys

**Instance-scoped (`unique_index :badge, :badge_index, within: Company`):**
- Manual indexing required
- Unique within parent only
- Requires parent context
- Examples: employee IDs, project names per team

### Unique vs Multi Indexing

**Unique index (`unique_index`):**
- 1:1 field-to-object mapping
- Returns single object or nil
- Enforces uniqueness within scope

**Multi index (`multi_index`):**
- 1:many field-to-objects mapping
- Returns array of objects
- Allows duplicate values

## Rebuilding Indexes

Indexes can be automatically rebuilt from source data using auto-generated rebuild methods:

```ruby
# Class-level indexes
User.rebuild_email_lookup      # Rebuilds from all User.email values
User.rebuild_username_lookup   # Rebuilds from all User.username values

# Instance-scoped indexes
company.rebuild_badge_index    # Rebuilds from all Employee.badge_number values
```

These methods work because **indexes are derived data** - they're computed from object field values.

> **Important:** Participation data (like `@team.members`) cannot be rebuilt automatically because participations represent business decisions, not derived data. See [Why Participations Can't Be Rebuilt](../../lib/familia/features/relationships/participation/rebuild_strategies.md) for the critical distinction between indexes and participations.

**When to rebuild indexes:**
- After data migrations or bulk imports
- Recovering from index corruption
- Adding indexes to existing data

## Performance Tips

### Bulk Operations

```ruby
# Efficient bulk indexing
employees.each_slice(100) do |batch|
  company.transaction do
    batch.each { |emp| emp.add_to_company_dept_index(company) }
  end
end
```

### Index Monitoring

```ruby
# Check index sizes
company.dept_index_engineering.size  # Count in engineering
User.email_lookup.size               # Total indexed emails

# Index distribution
%w[engineering sales marketing].map { |dept|
  [dept, company.send("dept_index_#{dept}").size]
}.to_h
```

### Cleanup

```ruby
# Remove orphaned entries
company.badge_index.to_h.each do |badge, emp_id|
  unless Employee.exists?(emp_id)
    company.badge_index.delete(badge)
  end
end
```

## Redis Key Patterns

| Type | Pattern | Example |
|------|---------|---------|
| Class unique | `{class}:{index_name}` | `user:email_lookup` |
| Instance unique | `{scope}:{id}:{index_name}` | `company:123:badge_index` |
| Multi-value | `{scope}:{id}:{index_name}:{value}` | `company:123:dept_index:engineering` |

## Troubleshooting

### Common Issues

**Query methods not generated:**
- Check `query: true` (default) or explicitly set
- Verify `feature :relationships` declared

**Index not updating:**
- Class indexes: automatic on save/destroy
- Instance indexes: require manual `add_to_*` calls

**Duplicate key errors:**
- Use `multi_index` for non-unique values
- Consider instance-scoped for contextual uniqueness

### Debugging

```ruby
# Check configuration
User.indexing_relationships
# => [{ field: :email, index_name: :email_lookup, ... }]

# Inspect index contents
User.email_lookup.to_h
# => {"alice@example.com" => "user_123", ...}

# Verify membership
employee.in_company_badge_index?(company)  # => true/false
```

## See Also

- [**Relationships Overview**](feature-relationships.md) - Core concepts
- [**Methods Reference**](feature-relationships-methods.md) - Complete API
- [**Participation Guide**](feature-relationships-participation.md) - Associations
