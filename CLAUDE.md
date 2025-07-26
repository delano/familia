# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
- **Run tests**: `bundle exec tryouts` (uses tryouts testing framework)
- **Run specific test file**: `bundle exec tryouts try/specific_test_try.rb`
- **Debug mode**: `FAMILIA_DEBUG=1 bundle exec tryouts`
- **Trace mode**: `FAMILIA_TRACE=1 bundle exec tryouts` (detailed Redis operation logging)

### Development Setup
- **Install dependencies**: `bundle install`
- **Generate documentation**: `bundle exec yard`
- **Code linting**: `bundle exec rubocop`

### Known Issues & Quirks
- **Reserved Keywords**: Cannot use `ttl`, `db`, `redis` as field names - use prefixed alternatives
- **Empty Identifiers**: Cause stack overflow in key generation - validate before operations
- **Connection Pool Race Conditions**: Thread safety issues under high concurrency
- **Manual Key Sync**: `key` field doesn't auto-sync with identifier changes
- **RedisType Redis Parameter**: `:redis` parameter silently ignored (missing setter)

### Debugging
- **Database command logging**: `tail plop.log` - Real-time Database command monitoring
  - Shows all Database operations with timestamps, database numbers, and full commands
  - Updates live as tests run or code executes
  - Essential for debugging Familia ORM Database interactions

### Testing Framework
This project uses `tryouts` instead of RSpec/Minitest. Test files are located in the `try/` directory and follow the pattern `*_try.rb`.

## Architecture Overview

### Core Components

**Familia**: A Valkey-compatible ORM library that provides Ruby object storage with advanced features like expiration, safe dumping, and quantization.

#### Primary Classes
1. **`Familia::Horreum`** - Base class for Valkey-backed objects (like ActiveRecord models)
   - Located in `lib/familia/horreum.rb`
   - Provides field definitions, data type relationships, and object lifecycle management
   - Supports multiple identifier strategies: symbols, procs, arrays

2. **`Familia::DataType`** - Base class for Valkey data type wrappers
   - Located in `lib/familia/datatype.rb`
   - Provides String, List, Set, SortedSet, HashKey implementations
   - Each type has its own class in `lib/familia/datatype/types/`

3. **`Familia::Base`** - Common module for both Horreum and DataType
   - Located in `lib/familia/base.rb`
   - Provides shared functionality and feature system

#### Feature System
Familia uses a modular feature system where features are mixed into classes:
- **Expiration** (`lib/familia/features/expiration.rb`) - TTL management with cascading
- **SafeDump** (`lib/familia/features/safe_dump.rb`) - API-safe object serialization
- **Quantization** (`lib/familia/features/quantization.rb`) - Time-based data bucketing

#### Key Architectural Patterns

**Inheritance Chain**: `MyClass < Familia::Horreum` automatically extends `ClassMethods` and `Features`

**DataType Definition**: Use class methods to define keystore database-backed attributes:
```ruby
class User < Familia::Horreum
  field :email        # Simple field
  list :sessions      # Valkey/Redis list
  set :tags           # Valkey/Redis set
  zset :metrics       # Valkey/Redis sorted set
  hashkey :settings   # Valkey/Redis hash
end
```

**Identifier Resolution**: Multiple strategies for object identification:
- Symbol: `identifier_field :email`
- Proc: `identifier ->(user) { "user:#{user.email}" }`
- Array: `identifier [:type, :email]`

### Directory Structure

- `lib/familia.rb` - Main entry point and module definition
- `lib/familia/horreum/` - Horreum class implementation (class_methods, commands, serialization, etc.)
- `lib/familia/datatype/` - Valkey/Redis type implementations and commands
- `lib/familia/features/` - Modular feature implementations
- `try/` - Test files using tryouts framework
- `try/test_helpers.rb` - Shared test utilities and sample classes

### Database Connection Management
- Connection handling in `lib/familia/connection.rb`
- Settings management in `lib/familia/settings.rb`
- Database selection via `logical_database` class method
- URI-based configuration support

### Important Implementation Notes

**Field Initialization**: Objects can be initialized with positional args (brittle) or keyword args (robust). Keyword args are recommended.

**Serialization**: Uses JSON by default but supports custom `serialize_value`/`deserialize_value` methods.

**Database Key Generation**: Automatic key generation using class name, identifier, and field/type names (aka dbkey). Pattern: `classname:identifier:fieldname`

**Memory Efficiency**: Only non-nil values are stored in keystore database to optimize memory usage.

**Thread Safety**: Data types are frozen after instantiation to ensure immutability.

## Common Patterns

### Defining a Horreum Class
```ruby
class Customer < Familia::Horreum
  feature :safe_dump
  feature :expiration

  identifier_field :custid
  default_expiration 5.years

  field :custid
  field :email
  list :sessions
  hashkey :settings
end
```

### Using Features
```ruby
# Safe dump for API responses
customer.safe_dump  # Returns only whitelisted fields

# Expiration management
customer.update_expiration(default_expiration: 1.hour)
```

### Transaction Support
```ruby
customer.transaction do |conn|
  conn.set("key1", "value1")
  conn.zadd("key2", score, member)
end
```
