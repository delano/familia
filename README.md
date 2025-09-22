# Familia - 2.0

**Organize and store Ruby objects in Valkey/Redis. A powerful Ruby ORM (of sorts) for Valkey/Redis.**

Familia provides a flexible and feature-rich way to interact with Valkey using Ruby objects. It's designed to make working with Valkey as natural as working with Ruby classes, while offering advanced features for complex data management.

## Quick Start

### 1. Installation

```bash
# Add to Gemfile
gem 'familia', '>= 2.0.0'

# Or install directly
gem install familia
```

### 2. Configure Connection

```ruby
# config/initializers/familia.rb (Rails)
# or at the top of your script

require 'familia'

# Basic configuration
Familia.uri = 'redis://localhost:6379/0'

# Or with authentication
Familia.uri = 'redis://user:password@localhost:6379/0'
```

### 3. Create Your First Model

```ruby
class User < Familia::Horreum
  identifier_field :email
  field :email
  field :name
  field :created_at
end
```

### 4. Basic Operations

```ruby
# Create
user = User.new(email: 'alice@example.com', name: 'Alice')
user.save

# Find
user = User.load('alice@example.com')

# Update
user.name = 'Alice Smith'
user.save

# Check existence
User.exists?('alice@example.com')  #=> true
```

## Prerequisites

- **Ruby**: 3.4+ (3.4+ recommended)
- **Valkey/Redis**: 6.0+
- **Gems**: `redis` (automatically installed)


## Usage Examples

### Creating and Saving Objects

```ruby
flower = Flower.create(name: "Red Rose", token: "rrose")
flower.owners.push("Alice", "Bob")
flower.tags.add("romantic")
flower.metrics.increment("views", 1)
flower.props[:color] = "red"
flower.save
```

### Retrieving and Updating Objects

```ruby
rose = Flower.find_by_id("rrose")
rose.name = "Pink Rose"
rose.save
```

### Using Safe Dump

```ruby
user = User.create(username: "rosedog", first_name: "Rose", last_name: "Dog")
user.safe_dump
# => {id: "user:rosedog", username: "rosedog", full_name: "Rose Dog"}
```

### Working with Time-based Data

```ruby
metric = DailyMetric.new
metric.counter.increment  # Increments the counter for the current hour
```

### Bulk Operations

```ruby
Flower.multiget("rrose", "tulip", "daisy")
```

### Transactional Operations

```ruby
user.transaction do |conn|
  conn.set("user:#{user.id}:status", "active")
  conn.zadd("active_users", Familia.now.to_i, user.id)
end
```

### Object Relationships

Familia includes a powerful relationships system for managing object associations:

```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid, :name, :email
  set :domains  # Collection for related objects

  # Automatic indexing and tracking
  class_indexed_by :email, :email_lookup
  class_participates_in :all_customers, score: :created_at
end

class Domain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id, :name, :status

  # Bidirectional membership
  participates_in Customer, :domains
end

# Clean, Ruby-like syntax
customer = Customer.new(custid: "cust123", email: "admin@acme.com")
customer.save  # Automatically indexed and participating

domain = Domain.new(domain_id: "dom456", name: "acme.com")
customer.domains << domain  # Clean collection syntax

# Fast O(1) lookups
found_customer = Customer.find_by_email("admin@acme.com")
```

## Advanced Features

### 🔗 Automatic Relationships with Ruby-like Syntax

Familia supports automatic bidirectional relationship management with explicit, Django-like relationship syntax:

```ruby
customer.domains << domain  # Automatically updates both sides
domain.in_customer_domains?(customer.custid)  # => true
```

### 🔐 Transparent Field Encryption

Built-in encryption with multiple providers, key rotation, and anti-tampering support.

```ruby
class SecureUser < Familia::Horreum
  feature :encrypted_fields
  encrypted_field :credit_card  # Automatically encrypted/decrypted
end

user.credit_card  # => ConcealedString("[CONCEALED]") - safe for logs
user.credit_card.reveal  # => "4111-1111-1111-1234" - explicit access
```

### Relationships and Associations

Familia provides three types of relationships with automatic management:

- **`member_of`** - Bidirectional membership with clean `<<` operator support
- **`indexed_by`** - O(1) hash-based field lookups (class-level or relationship-scoped)
- **`participates_in`** - Scored collections for rankings, time-series, and analytics

All relationships support automatic indexing and tracking - objects are automatically added to class-level collections when saved, with no manual management required.

## Organizing Complex Models

For large applications, you can organize model complexity using custom features and the Feature Autoloading System:

### Feature Autoloading System

Familia automatically discovers and loads feature-specific configuration files, enabling clean separation between core model definitions and feature configurations:

```ruby
# app/models/user.rb - Clean model definition
class User < Familia::Horreum
  field :name, :email, :password
  feature :safe_dump  # Configuration auto-loaded
end

# app/models/user/safe_dump_extensions.rb - Automatically discovered
class User
  safe_dump_fields :name, :email  # password excluded for security
end
```

Extension files follow the pattern: `{model_name}/{feature_name}_*.rb`

### Self-Registering Features

```ruby
# app/features/customer_management.rb
module MyApp::Features::CustomerManagement
  Familia::Base.add_feature(self, :customer_management)

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def create_with_validation(attrs)
      # Complex creation logic
    end
  end

  def complex_business_method
    # Instance methods
  end
end

# models/customer.rb
class Customer < Familia::Horreum
  field :email, :name
  feature :customer_management  # Clean model definition
end
```

These approaches keep complex models organized while maintaining Familia's clean, declarative style. For detailed migration information, see the [migration guides](docs/migrating/).

## AI Development Assistance

This version of Familia was developed with assistance from AI tools. The following tools provided significant help with architecture design, code generation, and documentation:

- **Google Gemini** - Refactoring, code generation, and documentation.
- **Claude Sonnet 4, Opus 4.1** - Architecture design, code generation, and documentation
- **Claude Desktop & Claude Code (Max plan)** - Interactive development sessions and debugging
- **GitHub Copilot** - Code completion and refactoring assistance
- **Qodo Merge Pro** - Code review and quality improvements

I remain responsible for all design decisions and the final code. I believe in being transparent about development tools, especially as AI becomes more integrated into our workflows as developers.

## Epilogue

For more information, visit:
- [Github Repository](https://github.com/delano/familia)
- [RubyGems Page](https://rubygems.org/gems/familia)

Contributions are welcome! Feel free to submit a Pull Request.


## Additional Documentation

- [Overview](file.overview.html)
- [Implementation Guide](file.implementation-guide.html)
- [API Reference](file.api-technical.html)
