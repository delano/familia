# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing

**Tryouts framework rules:**
1. **Structure**: Each file has 3 sections - setup (optional), testcases, teardown (optional); each testcase has 3 required parts: description, code, expectations.
2. **Test cases**: Use `##` line prefix for test descriptions, Ruby code, then `#=>` expectations
3. **Variables**: Instance variables (`@var`) persist across sections; local variables do not.
4. **Expectations**: Multiple expectation types available (`#=>`, `#==>`, `#=:>`, `#=!>`, etc.); each testcase can have multiple expectations.
5. **Comments**: Use single `#` prefix, but DO NOT label file sections
6. **Philosophy**: Plain realistic code, avoid mocks/test DSL
7. **Result**: Last expression in each test case is the result

**Running tests:**
- **Basic**: `bundle exec try` (auto-discovers `*_try.rb` and `*.try.rb` files)
- **All options**: `bundle exec try --help` (complete CLI reference with agent-specific notes)

**Agent-optimized workflow:**
- **Default agent mode**: `bundle exec try --agent` (structured, token-efficient output for LLMs)
- **Focus modes**: `bundle exec try --agent --agent-focus summary` (options: `summary|first-failure|critical`)
  - `summary`: Overview of test results only
  - `first-failure`: Stop at first failure with details
  - `critical`: Only show critical issues and summary

**Framework integration:**
- **RSpec**: `bundle exec try --rspec` (generates RSpec-compatible output)
- **Minitest**: `bundle exec try --minitest` (generates Minitest-compatible output)

**Debugging options:**
- **Stack traces**: `bundle exec try -s` (stack traces without debug logging)
- **Verbose failures**: `bundle exec try -vfs` (detailed failure output)
- **Debug mode**: `bundle exec try -D` (additional logging including stack traces)
- **Shared context**: `bundle exec try --shared-context` (DEFAULT - reuse shared context across setup, testcases, and teardown)
- **Fresh context**: `bundle exec try --no-shared-context` (isolate test cases, no shared variables)

*Note: Use `--agent` mode for optimal token efficiency when analyzing test results programmatically.*


### Development Setup
- **Install dependencies**: `bundle install`
- **Generate documentation**: `bundle exec yard`
- **Code linting**: `bundle exec rubocop`

### Changelog Management

Add changelog fragment with each user-facing or documented change (optional but encouraged). Fragments use RST format. See:
@changelog.d/README.md

### Known Issues & Quirks
- **Reserved Keywords**: Cannot use `ttl`, `db`, `valkey`, `redis` as field names - use prefixed alternatives
- **Empty Identifiers**: Cause stack overflow in key generation - validate before operations
- **Connection Pool Race Conditions**: Thread safety issues under high concurrency

### Debugging
- **Database command logging**: You can request real-time Database command monitoring from the user
  - Shows all Database operations with timestamps, database numbers, and full commands
  - Updates live as tests run or code executes
  - Essential for debugging Familia ORM Database interactions, multi/exec, pipelining, logical_database issues

## Architecture Overview

### Core Components

**Familia**: A Valkey-compatible ORM library that provides Ruby object storage with advanced features like expiration, safe dumping, and quantization.

#### Primary Classes
1. **`Familia::Horreum`** - Base class for Valkey-backed objects (like ActiveRecord models)
   - Located in `lib/familia/horreum.rb`
   - Provides field definitions, data type relationships, and object lifecycle management
   - Supports multiple identifier strategies: symbols, procs, arrays

2. **`Familia::DataType`** - Base class for Valkey data type wrappers
   - Located in `lib/familia/data_type.rb`
   - Provides String, List, UnsortedSet, SortedSet, HashKey implementations
   - Each type has its own class in `lib/familia/data_type/types/`

3. **`Familia::Base`** - Common module for both Horreum and DataType
   - Located in `lib/familia/base.rb`
   - Provides shared functionality and feature system

#### Feature System
Familia uses a modular feature system where features are mixed into classes:
- **Expiration** (`lib/familia/features/expiration.rb`) - TTL management with cascading
- **SafeDump** (`lib/familia/features/safe_dump.rb`) - API-safe object serialization
- **Relationships** (`lib/familia/features/relationships.rb`) - CRUD operations for related objects

#### Key Architectural Patterns

**Inheritance Chain**: `MyClass < Familia::Horreum` automatically extends `ClassMethods` and `Features`

**Common Pitfall: Overriding initialize**

⚠️ **Do NOT override `initialize` without calling `super`** - this breaks related field initialization.

**Bad - will cause crashes:**
```ruby
class User < Familia::Horreum
  def initialize(email)
    @email = email  # Missing super! Related fields won't work
  end
end
```

**Good - use the `init` hook instead:**
```ruby
class User < Familia::Horreum
  def init(email = nil)
    @email = email  # Called after super, related fields work
  end
end
```

**Good - call super explicitly:**
```ruby
class User < Familia::Horreum
  def initialize(email = nil, **kwargs)
    super(**kwargs)  # ✓ Related fields initialized
    @email = email
  end
end
```

**Why this matters**: Familia's `initialize` method calls `initialize_relatives` to set up DataType objects (lists, sets, etc.). Without calling `super`, these objects remain nil and you'll get helpful errors pointing to the missing super call.

**When to use each approach:**
- **Use `init` hook** (preferred): For simple initialization logic that doesn't need to intercept constructor arguments. The `init` method is called automatically after `super` with the same arguments passed to `new`.
- **Use explicit `super`**: When you need full control over initialization order or need to transform arguments before passing to parent. Remember to pass `**kwargs` to preserve keyword argument handling.

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

### Database Connection Management
- Connection handling in `lib/familia/connection.rb`
- Settings management in `lib/familia/settings.rb`
- Database selection via `logical_database` class method
- URI-based configuration support

### Important Implementation Notes

**Field Initialization**: Objects can be initialized with positional args (brittle) or keyword args (robust). Keyword args are recommended. All non-nil values including `false` and `0` are preserved during initialization.

**Serialization**: All field values are JSON-encoded for storage and JSON-decoded on retrieval to preserve Ruby types (Integer, Boolean, String, Float, Hash, Array, nil). This ensures type preservation across the Redis storage boundary. For example:
- `age: 35` (Integer) stores as `"35"` in Redis and loads back as Integer `35`
- `active: true` (Boolean) stores as `"true"` in Redis and loads back as Boolean `true`
- `metadata: {key: "value"}` (Hash) stores as JSON and loads back as Hash with proper types

**Database Key Generation**: Automatic key generation using class name, identifier, and field/type names (aka dbkey). Pattern: `classname:identifier:fieldname`

**Memory Efficiency**: Only non-nil values are stored in keystore database to optimize memory usage.

**Thread Safety**: Data types are frozen after instantiation to ensure immutability.
