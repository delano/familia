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
  conn.zadd("active_users", Time.now.to_i, user.id)
end
```

## Conclusion

Familia provides a powerful and flexible way to work with Valkey-compatible in Ruby applications. Its features like automatic expiration, safe dumping, and quantization make it suitable for a wide range of use cases, from simple key-value storage to complex time-series data management.

For more information, visit:
- [Github Repository](https://github.com/delano/familia)
- [RubyGems Page](https://rubygems.org/gems/familia)

Contributions are welcome! Feel free to submit a Pull Request.
