# Relationship Methods

Here are the methods automatically generated for each relationship type in the new clean API:

## member_of Relationships

When you declare:
```ruby
class Domain < Familia::Horreum
  member_of Customer, :domains
end
```

**Generated methods on Domain instances:**
- `add_to_customer_domains(customer)` - Add this domain to customer's domains collection
- `remove_from_customer_domains(customer)` - Remove this domain from customer's domains collection
- `in_customer_domains?(customer)` - Check if this domain is in customer's domains collection

**Collection << operator support:**
```ruby
customer.domains << domain  # Clean Ruby-like syntax (equivalent to domain.add_to_customer_domains(customer))
```

The method names follow the pattern: `{action}_to_{lowercase_class_name}_{collection_name}`

## participates_in Relationships

### Class-Level Tracking (class_participates_in)
When you declare:
```ruby
class Customer < Familia::Horreum
  class_participates_in :all_customers, score: :created_at
end
```

**Generated class methods:**
- `Customer.add_to_all_customers(customer)` - Add customer to class-level tracking
- `Customer.remove_from_all_customers(customer)` - Remove customer from class-level tracking
- `Customer.all_customers` - Access the sorted set collection directly

**Automatic behavior:**
- Objects are automatically added to class-level tracking collections when saved
- No manual calls required for basic tracking

### Relationship Tracking (participates_in with parent class)
When you declare:
```ruby
class User < Familia::Horreum
  participates_in Team, :active_users, score: :last_seen
end
```

**Generated methods:**
- Team instance methods for managing the active_users collection
- Automatic score calculation based on the provided lambda or field

## indexed_by Relationships

The `indexed_by` method creates Valkey/Redis hash-based indexes for O(1) field lookups with automatic management.

### Class-Level Indexing (class_indexed_by)
When you declare:
```ruby
class Customer < Familia::Horreum
  class_indexed_by :email, :email_lookup
end
```

**Generated methods:**
- **Instance methods**: `customer.add_to_class_email_lookup`, `customer.remove_from_class_email_lookup`
- **Class methods**: `Customer.email_lookup` (returns hash), `Customer.find_by_email(email)`

**Automatic behavior:**
- Objects are automatically added to class-level indexes when saved
- Index updates happen transparently on field changes

Redis key pattern: `customer:email_lookup`

### Relationship-Scoped Indexing (indexed_by with context:)
When you declare:
```ruby
class Domain < Familia::Horreum
  indexed_by :name, :domain_index, target: Customer
end
```

**Generated instance methods on Customer:**
- `customer.find_by_name(domain_name)` - Find domain by name within this customer
- `customer.find_all_by_name(domain_names)` - Find multiple domains by names

Redis key pattern: `customer:customer_id:domain_index:field_value` (parent-scoped with field value)

### When to Use Each Context
- **Class-level context (`class_indexed_by`)**: Use for system-wide lookups where the field value should be unique across all instances
  - Examples: email addresses, usernames, API keys
- **Relationship context (`context:` parameter)**: Use for relationship-scoped lookups where the field value is unique within a specific context
  - Examples: domain names per customer, project names per team

## Complete Example

From the relationships example file, you can see the new clean API in action:

```ruby
# Domain declares membership in Customer collections
class Domain < Familia::Horreum
  member_of Customer, :domains
  class_participates_in :active_domains, score: -> { status == 'active' ? Time.now.to_i : 0 }
end

class Customer < Familia::Horreum
  class_indexed_by :email, :email_lookup
  class_participates_in :all_customers, score: :created_at
end
```

**Usage with automatic behavior:**
```ruby
# Create and save objects (automatic indexing and tracking)
customer = Customer.new(email: "admin@acme.com", name: "Acme Corp")
customer.save  # Automatically added to email_lookup and all_customers

domain = Domain.new(name: "acme.com", status: "active")
domain.save    # Automatically added to active_domains

# Clean relationship syntax
customer.domains << domain  # Ruby-like collection syntax

# Query relationships
domain.in_customer_domains?(customer)         # => true
customer.domains.member?(domain.identifier)   # => true

# O(1) lookups with automatic management
found_id = Customer.email_lookup.get("admin@acme.com")
```

## Method Naming Conventions

The relationship system uses consistent naming patterns:
- **member_of**: `{add_to|remove_from|in}_#{parent_class.downcase}_#{collection_name}`
- **class_participates_in**: `{add_to|remove_from}_#{collection_name}` (class methods)
- **class_indexed_by**: `{add_to|remove_from}_class_#{index_name}` (instance methods)
- **indexed_by with context**: `{add_to|remove_from}_#{context_class.downcase}_#{index_name}` (instance methods)

## Key Benefits

- **Automatic management**: Save operations update indexes and tracking automatically
- **Ruby-idiomatic**: Use `<<` operator for natural collection syntax
- **Consistent storage**: All indexes stored at class level for architectural simplicity
- **Clean API**: Removed complex global vs parent conditionals for simpler method generation


## Context Parameter Usage Patterns

The `context` parameter in `indexed_by` is a fundamental architectural decision that determines index scope and ownership. Here are practical patterns for when to use each approach:

### Global Context Pattern
Use `class_indexed_by` when field values should be unique system-wide:

```ruby
class User < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id, :email, :username

  # System-wide unique email lookup
  class_indexed_by :email, :email_lookup
  class_indexed_by :username, :username_lookup
end

# Usage:
user.add_to_global_email_lookup
found_user_id = User.email_lookup.get("john@example.com")
```

**Redis keys generated**: `global:email_lookup`, `global:username_lookup`

### Context-Scoped Pattern
Use `context: SomeClass` when field values are unique within a specific context:

```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid, :name
  sorted_set :domains
end

class Domain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id, :name, :subdomain

  # Domains are unique per customer (customer can't have duplicate domain names)
  indexed_by :name, :domain_index, target: Customer
  indexed_by :subdomain, :subdomain_index, target: Customer
end

# Usage:
customer = Customer.new(custid: "cust_123")
customer.find_by_name("example.com")           # Find domain within this customer
customer.find_all_by_subdomain(["www", "api"]) # Find multiple subdomains
```

**Redis keys generated**: `customer:cust_123:domain_index:example.com`, `customer:cust_123:subdomain_index:www`

### Mixed Pattern Example
A real-world example showing both patterns:

```ruby
class ApiKey < Familia::Horreum
  feature :relationships

  identifier_field :key_id
  field :key_id, :key_hash, :name, :scope

  # API key hashes must be globally unique
  class_indexed_by :key_hash, :global_key_lookup

  # But key names can be reused across different customers
  indexed_by :name, :customer_key_lookup, target: Customer
  indexed_by :scope, :scope_lookup, target: Customer
end

# Usage examples:
# Global lookup (system-wide unique)
ApiKey.key_lookup.get("sha256:abc123...")

# Scoped lookup (unique per customer)
customer = Customer.new(custid: "cust_456")
customer.find_by_name("production-api-key")
customer.find_all_by_scope(["read", "write"])
```

### Migrating Guide
If you have existing code with old syntax, here's how to update it:

```ruby
# ❌ Old syntax (pre-refactoring)
indexed_by :email_lookup, field: :email
indexed_by :email, :email_lookup, target: :global
participates_in :global, :all_users, score: :created_at

# ✅ New syntax - Class-level scope
class_indexed_by :email, :email_lookup
class_participates_in :all_users, score: :created_at

# ✅ New syntax - Relationship scope
indexed_by :email, :customer_email_lookup, target: Customer
participates_in Customer, :user_activity, score: :last_seen
```

**Key Changes**:
1. **Class-level relationships**: Use `class_` prefix (`class_participates_in`, `class_indexed_by`)
2. **Relationship-scoped**: Use `target:` parameter instead of `:global` symbol
3. **Automatic management**: Objects automatically added to class-level collections on save
4. **Clean syntax**: Collections support `<<` operator for Ruby-like relationship building
5. **Simplified storage**: All indexes stored at class level (parent is conceptual only)

**Behavioral Changes**:
- Save operations now automatically update indexes and class-level tracking
- No more manual `add_to_*` calls required for basic functionality
- `<<` operator works naturally with all collection types
- Method generation simplified without complex global/parent conditionals
