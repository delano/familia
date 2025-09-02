# Relationship methods

here are the methods automatically generated for each relationship type:

member_of Relationships

When you declare:
class Domain < Familia::Horreum
  member_of Customer, :domains, type: :set
end

Generated methods on Domain instances:
- add_to_customer_domains(customer_id) - Add this domain to customer's domains collection
- remove_from_customer_domains(customer_id) - Remove this domain from customer's domains collection
- in_customer_domains?(customer_id) - Check if this domain is in customer's domains collection

The method names follow the pattern: {action}_to_{lowercase_class_name}_{collection_name}

tracked_in Relationships

**Global Tracking (New class_ prefix convention)**
When you declare:
class Customer < Familia::Horreum
  class_tracked_in :all_customers, score: :created_at
end

Generated class methods:
- Customer.add_to_all_customers(customer) - Add customer to global tracking
- Customer.remove_from_all_customers(customer) - Remove customer from global tracking
- Customer.all_customers - Access the sorted set collection directly

**Scoped Tracking (tracked_in with class context)**
When you declare:
tracked_in Team, :active_users, score: :last_seen
Generates: Team instance methods for managing the active_users collection

indexed_by Relationships

The `indexed_by` method creates Redis hash-based indexes for O(1) field lookups.

**Global Context (New class_ prefix convention)**
When you declare:
```ruby
class Customer < Familia::Horreum
  class_indexed_by :email, :email_lookup
end
```

Generated methods:
- **Instance methods**: `customer.add_to_global_email_lookup`, `customer.remove_from_global_email_lookup`
- **Class methods**: `Customer.email_lookup` (returns hash), `Customer.find_by_email(email)`

Redis key pattern: `global:email_lookup`

**Parent Context (Per-Instance Index)**
When you declare:
```ruby
class Domain < Familia::Horreum
  indexed_by :name, :domain_index, parent: Customer
end
```

Generated class methods on Customer:
- Customer.find_by_name(domain_name) - Find domain by name within this customer
- Customer.find_all_by_name(domain_names) - Find multiple domains by names

Redis key pattern: `customer:123:domain_index` (per customer instance)

**When to Use Each Context**
- **Global context (`class_indexed_by`)**: Use for system-wide lookups where the field value should be unique across all instances
  - Examples: email addresses, usernames, API keys
- **Parent context (`parent:` parameter)**: Use for scoped lookups where the field value is unique within a specific parent object
  - Examples: domain names per customer, project names per team

Example from the Codebase

From the relationships example file, you can see this in action:

# Domain declares membership in Customer collections
class Domain < Familia::Horreum
  member_of Customer, :domains, type: :set
end

# This generates these methods on Domain instances:
domain.add_to_customer_domains(customer.custid)     # Add to relationship
domain.remove_from_customer_domains(customer.custid) # Remove from relationship
domain.in_customer_domains?(customer.custid)       # Query membership

# For tracked_in relationships:
Customer.add_to_all_customers(customer)    # Class method
Customer.all_customers.range(0, -1)        # Direct collection access

# For indexed_by relationships:
customer.add_to_global_email_lookup                        # Instance method
Customer.email_lookup.get("user@example.com")       # O(1) lookup

Method Naming Conventions

The relationship system uses consistent naming patterns:
- member_of: {add_to|remove_from|in}_#{parent_class.downcase}_#{collection_name}
- tracked_in: {add_to|remove_from}_#{collection_name} (class methods)
- indexed_by: {add_to|remove_from}_#{index_name} (class methods)

This automatic method generation creates a clean, predictable API that handles both the Redis operations and maintains referential consistency
across related objects.


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

### Parent Context Pattern
Use `parent: SomeClass` when field values are unique within a specific parent context:

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
  indexed_by :name, :domain_index, parent: Customer
  indexed_by :subdomain, :subdomain_index, parent: Customer
end

# Usage:
customer = Customer.new(custid: "cust_123")
customer.find_by_name("example.com")           # Find domain within this customer
customer.find_all_by_subdomain(["www", "api"]) # Find multiple subdomains
```

**Redis keys generated**: `customer:cust_123:domain_index`, `customer:cust_123:subdomain_index`

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
  indexed_by :name, :customer_key_lookup, parent: Customer
  indexed_by :scope, :scope_lookup, parent: Customer
end

# Usage examples:
# Global lookup (system-wide unique)
ApiKey.key_lookup.get("sha256:abc123...")

# Scoped lookup (unique per customer)
customer = Customer.new(custid: "cust_456")
customer.find_by_name("production-api-key")
customer.find_all_by_scope(["read", "write"])
```

### Migration Guide
If you have existing code with old syntax, here's how to update it:

```ruby
# ❌ Old syntax
indexed_by :email_lookup, field: :email
indexed_by :email, :email_lookup, context: :global
tracked_in :global, :all_users, score: :created_at

# ✅ New syntax - Global scope
class_indexed_by :email, :email_lookup
class_tracked_in :all_users, score: :created_at

# ✅ New syntax - Parent scope
indexed_by :email, :customer_email_lookup, parent: Customer
tracked_in Customer, :user_activity, score: :last_seen
```

**Key Changes**:
1. Global relationships use `class_` prefix: `class_tracked_in`, `class_indexed_by`
2. Scoped relationships use `parent:` instead of `context:`
3. No more `:global` symbol - use class_ prefix methods instead
4. Consistent with Horreum's established class_ prefix convention
