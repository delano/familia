# Familia - 2.0

**Organize and store Ruby objects in Valkey/Redis using native database types (an ORM of sorts).**

Familia provides object-oriented access to Valkey/Redis using their database types. Unlike traditional ORMs that map objects to relational tables, Familia maps Ruby objects directly to Valkey's native data structures (strings, lists, sets, sorted sets, hashes) as instance variables.

> [!CAUTION]
> Familia 2 is in pre-release and not ready for production use. (September 2025)
## Traditional ORM vs Familia

**Traditional ORMs** convert your objects to SQL tables. A product with categories becomes two tables with a join table. Checking if a tag exists requires a query with joins.

**Familia** stores your objects using Redis data structures directly. A product with categories uses an actual Redis list. Checking if a tag exists is a native O(1) Redis operation.

```ruby
# Traditional ORM - everything becomes SQL tables
class Product < ActiveRecord::Base
  has_and_belongs_to_many :tags  # Creates products_tags junction table
end

product.tags.include?(tag)  # SELECT * FROM products_tags WHERE ...

# Familia - uses Redis data types directly
class Product < Familia::Horreum
  set :tags                  # Actual Redis set
end

product.tags.include?("electronics")  # Redis SISMEMBER - O(1) operation
```

### What This Means in Practice

When you define a Familia model, each data type declaration creates the corresponding Redis structure:

```ruby
class Product < Familia::Horreum
  identifier_field :sku

  field :name, :price        # Stored in Redis hash
  list :categories           # Actual Redis list
  set :tags                  # Actual Redis set
  zset :ratings              # Actual Redis sorted set
  counter :views             # Redis string with atomic increment
end

# These are Redis native operations, not ORM abstractions
product.categories.push("electronics")   # LPUSH
product.tags.add("popular")              # SADD
product.ratings.add(4.5, "user123")      # ZADD with score
product.views.increment                  # INCR (atomic)
```

The performance characteristics you rely on in Redis remain unchanged. Set membership is O(1). Sorted sets maintain order automatically. Counters increment atomically without read-modify-write cycles.

## Quick Start

### 1. Installation

```bash
# Add to Gemfile
gem 'familia', '>= 2.0'

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
# Create and save
user = User.create(email: 'alice@example.com', name: 'Alice', created_at: Time.now.to_i)

# Find by identifier
user = User.load('alice@example.com')

# Update and save
user.name = 'Alice Windows'
user.save

# Fast update (immediate persistence)
user.name!('Alice Smith')  # Sets and saves immediately

# Check existence
User.exists?('alice@example.com')  #=> true

# Delete
user.destroy

# Conditional save
user.save_if_not_exists  # Only saves if object doesn't exist yet
```

### 5. Generated Method Patterns

Familia automatically generates methods for fields and data types:

```ruby
class User < Familia::Horreum
  field :name                    # → name, name=, name!
  set :tags                      # → tags, tags=, tags?
  list :history                  # → history, history=, history?
end

# Field methods
user.name                        # Get field value
user.name = 'Alice'              # Set field value
user.name!('Alice')              # Set and save immediately

# Data type methods
user.tags                        # Get Set instance
user.tags = new_set              # Replace Set instance
user.tags?                       # Check if it's a Set type
```

## Prerequisites

- **Ruby**: 3.4+ (3.4+ recommended)
- **Valkey/Redis**: 6.0+
- **Gems**: `redis` (automatically installed)

---

## Core Concepts

### Data Types

Familia provides direct mappings to Valkey/Redis native data structures:

```ruby
class BlogPost < Familia::Horreum
  identifier_field :slug

  # Basic fields
  field :slug, :title, :content, :published_at

  # Redis data types as instance variables
  string :view_count, default: '0'           # Atomic counters
  list :comments                             # Ordered, allows duplicates
  set :tags                                  # Unique values
  zset :popularity_scores                    # Scored/ranked data
  hashkey :metadata                          # Key-value pairs

  # Advanced field types
  counter :likes                             # Specialized atomic counter
end

post = BlogPost.create(slug: "hello-world", title: "Hello World")

# Work with Redis data types naturally
post.view_count.increment                    # INCR view_count
post.comments.push("Great post!")           # LPUSH comments
post.tags.add("ruby", "programming")        # SADD tags
post.popularity_scores.add(4.5, "user123") # ZADD popularity_scores
post.metadata["author"] = "Alice"           # HSET metadata
post.likes.increment(5)                     # INCRBY likes 5
```

### Features System

Enable advanced functionality with Familia's modular feature system:

```ruby
class User < Familia::Horreum
  # Enable features as needed
  feature :expiration                        # TTL management
  feature :safe_dump                         # API-safe serialization
  feature :encrypted_fields                  # Field-level encryption
  feature :relationships                     # Object relationships
  feature :object_identifier                 # Auto-generated IDs
  feature :quantization                      # Time-based data bucketing

  identifier_field :email
  field :email, :name, :created_at

  # Feature-specific functionality
  encrypted_field :api_key                   # Automatically encrypted
  safe_dump_field :email                     # Include in safe_dump
  safe_dump_field :name                      # Include in safe_dump
  default_expiration 30.days                # Auto-expire inactive users
end

user = User.create(email: "alice@example.com", api_key: "secret123")
user.api_key.class                          # => ConcealedString
user.api_key.to_s                           # => "[CONCEALED]" (safe for logs)
user.safe_dump                              # => {email: "...", name: "..."}
```

### Querying and Finding

```ruby
# Primary key lookup
user = User.load("alice@example.com")

# Existence checks
User.exists?("alice@example.com")           # => true/false

# Bulk operations
users = User.multiget("alice@example.com", "bob@example.com")

# With relationships feature - indexed lookups
class User < Familia::Horreum
  feature :relationships
  field :email, :username
  class_indexed_by :username, :username_lookup
end

# O(1) indexed finding
user = User.find_by_username("alice_doe")   # Fast hash lookup
```

---

## Usage Examples

### Creating and Saving Objects

```ruby
flower = Flower.create(name: "Red Rose", token: "prose")
flower.owners.push("Alice", "Bob")
flower.tags.add("romantic")
flower.metrics.increment("views", 1)
flower.props[:color] = "red"
flower.save
```

### Retrieving and Updating Objects

```ruby
rose = Flower.load("prose")
rose.name = "Pink Rose"
rose.save
```

### Using Safe Dump

```ruby
user = User.create(username: "prosedog", first_name: "Rose", last_name: "Dog")
user.safe_dump
# => {id: "user:prosedog", username: "prosedog", full_name: "Rose Dog"}
```

### Working with Time-based Data

```ruby
metric = DailyMetric.new
metric.counter.increment  # Increments the counter for the current hour
```

### Bulk Operations

```ruby
Flower.multiget("prose", "tulip", "daisy")
```

### Transactional Operations

```ruby
user.transaction do |conn|
  conn.set("user:#{user.id}:status", "active")
  conn.zadd("active_users", Familia.now.to_i, user.id)
end
```

### Advanced Patterns

**Time-based Expiration:**
```ruby
class Session < Familia::Horreum
  feature :expiration
  default_expiration 24.hours

  field :user_id, :token
end

session = Session.create(user_id: "123", token: "abc123")
session.ttl                                 # Check remaining time
session.expire_in(1.hour)                  # Custom expiration
```

**Encrypted Fields:**
```ruby
class SecureData < Familia::Horreum
  feature :encrypted_fields

  field :name
  encrypted_field :credit_card, :ssn
end

data = SecureData.create(name: "Alice", credit_card: "4111-1111-1111-1234")
data.credit_card.reveal                     # => "4111-1111-1111-1234"
data.credit_card.to_s                       # => "[CONCEALED]"
```

## Configuration

### Basic Setup

```ruby
# config/initializers/familia.rb (Rails)
require 'familia'

# Basic configuration
Familia.uri = 'redis://localhost:6379/0'

# Production configuration
Familia.configure do |config|
  config.redis_uri = ENV['REDIS_URL']
  config.debug = ENV['FAMILIA_DEBUG'] == 'true'
end
```

### Connection Pooling

```ruby
require 'connection_pool'

Familia.connection_provider = lambda do |uri|
  ConnectionPool.new(size: 10, timeout: 5) do
    Redis.new(url: uri)
  end.with { |conn| yield conn if block_given?; conn }
end
```

### Encryption Setup

```ruby
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY_V1'],
    v2: ENV['FAMILIA_ENCRYPTION_KEY_V2']
  }
  config.current_key_version = :v2
end
```

## Organizing Complex Models

For large applications, you can organize model complexity using custom features and the Feature Autoloading System:

### Feature Organization with Autoloader

For large applications, organize features into modular files using the autoloader:

```ruby
# app/models/customer.rb - Main model file
class Customer < Familia::Horreum
  module Features
    include Familia::Features::Autoloader
    # Automatically loads all .rb files from app/models/customer/features/
  end

  identifier_field :custid
  field :custid, :name, :email
  feature :safe_dump                        # Feature configuration loaded automatically
end

# app/models/customer/features/notifications.rb - Automatically loaded
module Customer::Features::Notifications
  def send_welcome_email
    NotificationService.send_template(
      email: email,
      template: 'customer_welcome',
      variables: { name: name, custid: custid }
    )
  end
end

# app/models/customer/features/safe_dump_extensions.rb - Feature-specific config
module Customer::Features::SafeDumpExtensions
  def self.included(base)
    base.safe_dump_field :custid
    base.safe_dump_field :name
    base.safe_dump_field :email
  end
end
```

This approach keeps complex models organized while maintaining clean, declarative style.

## AI Development Assistance

This version of Familia was developed with assistance from AI tools. The following tools provided significant help with architecture design, code generation, and documentation:

- **Google Gemini** - Refactoring, code generation, and documentation.
- **Claude Sonnet 4, Opus 4.1** - Architecture design, code generation, and documentation
- **Claude Desktop & Claude Code (Max plan)** - Interactive development sessions and debugging
- **GitHub Copilot** - Code completion and refactoring assistance
- **Qodo Merge Pro** - Code review and quality improvements

I remain responsible for all design decisions and the final code. I believe in being transparent about development tools, especially as AI becomes more integrated into our workflows as developers.

## Links

- [Github Repository](https://github.com/delano/familia)
- [RubyGems Page](https://rubygems.org/gems/familia)

## Documentation

For comprehensive guides and detailed technical information:

- **[Overview Guide](docs/overview.md)** - Conceptual understanding and getting started
- **[Technical Reference](docs/reference/api-technical.md)** - Implementation details and advanced patterns
- **[Migration Guides](docs/migrating/)** - Upgrading from previous versions

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
