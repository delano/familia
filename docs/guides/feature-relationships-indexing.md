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
| `multi_index` | Class (default) | Global non-unique groupings | Redis Set per value |
| `multi_index` | Instance | Parent-scoped groupings | Redis Set per value |

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

## Class-Level Multi-Value Indexing

Class-level multi-value indexes group objects by field values at the class level. This is the default behavior when no `within:` parameter is specified.

```ruby
class Customer < Familia::Horreum
  feature :relationships
  field :role

  # Class-level multi_index (within: :class is the default)
  multi_index :role, :role_index
end

# Create customers with various roles
alice = Customer.create(custid: 'cust_001', role: 'admin')
bob = Customer.create(custid: 'cust_002', role: 'user')
charlie = Customer.create(custid: 'cust_003', role: 'admin')

# Manually add to index (or use auto-indexing via save hooks)
alice.add_to_class_role_index
bob.add_to_class_role_index
charlie.add_to_class_role_index

# Query all customers with a specific role
admins = Customer.find_all_by_role('admin')  # => [alice, charlie]
users = Customer.find_all_by_role('user')    # => [bob]

# Random sampling
sample = Customer.sample_from_role('admin', 1)  # => [random admin]
```

### Redis Key Pattern

Class-level multi-indexes use the pattern: `{classname}:{index_name}:{field_value}`

```ruby
Customer.role_index_for('admin').dbkey  # => "customer:role_index:admin"
Customer.role_index_for('user').dbkey   # => "customer:role_index:user"
```

### Generated Class Methods

| Method | Description |
|--------|-------------|
| `Customer.role_index_for(value)` | Factory returning `Familia::UnsortedSet` for the field value |
| `Customer.find_all_by_role(value)` | Find all objects with that field value |
| `Customer.sample_from_role(value, count)` | Random sample of objects |
| `Customer.rebuild_role_index` | Rebuild the entire index from source data |

### Generated Instance Methods

| Method | Description |
|--------|-------------|
| `customer.add_to_class_role_index` | Add this object to its field value's index |
| `customer.remove_from_class_role_index` | Remove this object from its field value's index |
| `customer.update_in_class_role_index(old_value)` | Move object from old index to new index |

### Update Operations

When a field value changes, use the update method to atomically move the object between indexes:

```ruby
old_role = customer.role
customer.role = 'superadmin'
customer.update_in_class_role_index(old_role)

# Customer is now in 'superadmin' index, removed from old 'admin' index
Customer.find_all_by_role('superadmin')  # => includes customer
Customer.find_all_by_role('admin')       # => no longer includes customer
```

## Instance-Scoped Multi-Value Indexing

For indexes scoped to a parent object, use `within:` to specify the scope class. This allows the same field values across different parent contexts.

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

### Generated Methods (Instance-Scoped)

**On scope class (Company):**
| Method | Description |
|--------|-------------|
| `company.dept_index_for(value)` | Factory returning UnsortedSet for value |
| `company.find_all_by_department(dept)` | Find all in department |
| `company.sample_from_department(dept, count)` | Random sample |
| `company.rebuild_dept_index` | Rebuild index from participation |

**On indexed class (Employee):**
| Method | Description |
|--------|-------------|
| `employee.add_to_company_dept_index(company)` | Add to company's index |
| `employee.remove_from_company_dept_index(company)` | Remove from index |
| `employee.update_in_company_dept_index(company, old_dept)` | Move between indexes |

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

**Class-level unique (`unique_index :email, :email_lookup`):**
- Automatic indexing on save/destroy
- System-wide uniqueness
- No parent context needed
- Examples: emails, usernames, API keys

**Class-level multi (`multi_index :role, :role_index`):**
- Default behavior (no `within:` needed)
- Groups all objects by field value at class level
- Manual indexing via instance methods
- Examples: roles, categories, statuses

**Instance-scoped (`unique_index :badge, :badge_index, within: Company`):**
- Manual indexing required
- Unique within parent only
- Requires parent context
- Examples: employee IDs, project names per team

**Instance-scoped multi (`multi_index :dept, :dept_index, within: Company`):**
- Groups objects by field value within parent scope
- Same field value allowed across different parents
- Manual indexing with parent context
- Examples: departments per company, tags per project

### Unique vs Multi Indexing

**Unique index (`unique_index`):**
- 1:1 field-to-object mapping
- Returns single object or nil
- Enforces uniqueness within scope

**Multi index (`multi_index`):**
- 1:many field-to-objects mapping
- Returns array of objects
- Allows duplicate values
- Default: class-level scope (use `within:` for instance scope)

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

## Index Storage Format

Index values (the object identifiers stored in hash keys and sets) are raw strings, not JSON-encoded. This is a deliberate design choice shared across all Familia collections that store object references — it ensures that lookups, membership checks, and key construction all operate on the same byte representation. See [Collection Member Serialization](field-system.md#collection-member-serialization) for the underlying serialization rules.

## Redis Key Patterns

| Type | Pattern | Example |
|------|---------|---------|
| Class unique | `{class}:{index_name}` | `user:email_lookup` |
| Class multi | `{class}:{index_name}:{value}` | `customer:role_index:admin` |
| Instance unique | `{scope}:{id}:{index_name}` | `company:123:badge_index` |
| Instance multi | `{scope}:{id}:{index_name}:{value}` | `company:123:dept_index:engineering` |

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
