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
- **Debug mode**: `bundle exec try -D` (additional logging including stack traces)
- **Verbose failures**: `bundle exec try -vf` (detailed failure output)
- **Fresh context**: `bundle exec try --fresh-context` (isolate test cases)

*Note: Use `--agent` mode for optimal token efficiency when analyzing test results programmatically.*


### Development Setup
- **Install dependencies**: `bundle install`
- **Generate documentation**: `bundle exec yard`
- **Code linting**: `bundle exec rubocop`

### Changelog Management

Add changelog fragment with each user-facing or documented change (optional but encouraged)

- When a commit contains a user-visible change (feature, bugfix, docs, behaviour change), create a Scriv fragment in `changelog.d/fragments/` at the same time as the code change.
  - Quick commands:
    - `scriv create --edit`
    - `git add changelog.d/fragments/your_fragment.md`
    - `git commit -m 'Short subject ≤50 chars'`
    - Release workflow:
      - `scriv collect --version 2.0.0-pre8` -- collects all fragments into CHANGELOG.md
  - Keep fragments bite-sized: one fragment per logical change.
  - Use the fragment categories: Added, Changed, Deprecated, Removed, Fixed, Security, Documentation.

### Known Issues & Quirks
- **Reserved Keywords**: Cannot use `ttl`, `db`, `valkey`, `redis` as field names - use prefixed alternatives
- **Empty Identifiers**: Cause stack overflow in key generation - validate before operations
- **Connection Pool Race Conditions**: Thread safety issues under high concurrency

### Debugging
- **Database command logging**: You can request real-time Database command monitoring from the user
  - Shows all Database operations with timestamps, database numbers, and full commands
  - Updates live as tests run or code executes
  - Essential for debugging Familia ORM Database interactions, multi/exec, pipelining, logical_database issues

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
   - Located in `lib/familia/data_type.rb`
   - Provides String, List, Set, SortedSet, HashKey implementations
   - Each type has its own class in `lib/familia/data_type/types/`

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
- `lib/familia/data_type/` - Valkey/Redis type implementations and commands
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
