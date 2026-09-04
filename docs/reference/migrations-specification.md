# 0131-migrations.txt
---
# Familia v2 Migration System Specification

**Version**: 2.0.0-draft
**Date**: 2026-01-31
**Status**: Proposal

---

## 1. Overview

This specification defines a Redis-native migration system for Familia v2. The implementation absorbs existing migration infrastructure from OneTimeSecret and extends it with orchestration capabilities inspired by redis-om-python.

---

## 2. Design Principles

1. **Redis as single source of truth** — Migration state stored in Redis, not files or SQL
2. **Reuse over rewrite** — Absorb battle-tested OTS migration code
3. **Layered architecture** — Core layer is Horreum-agnostic; model layer optional
4. **Idempotent execution** — Safe to re-run; applied migrations skip automatically
5. **Reversibility where possible** — Optional `down()` methods for rollback

---

## 3. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Application Layer                          │
│  User-defined migrations                                      │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│           ABSORBED FROM OTS (with extensions)                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────┐ │
│  │  BaseMigration  │  │ ModelMigration  │  │   Pipeline    │ │
│  │  + migration_id │  │   (as-is)       │  │   Migration   │ │
│  │  + dependencies │  │                 │  │   (as-is)     │ │
│  │  + down()       │  │                 │  │               │ │
│  └─────────────────┘  └─────────────────┘  └───────────────┘ │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                    NEW FOR FAMILIA                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │  Registry   │  │   Runner    │  │   Script    │           │
│  │  (tracking) │  │ (ordering)  │  │ (Lua atoms) │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                      Familia::Base                            │
│  Redis connection, sorted_set, hashkey primitives             │
└──────────────────────────────────────────────────────────────┘
```

---

## 4. Code Inventory

### 4.1 Absorb from OTS (Extract into Familia)

These files move from `onetimesecret` to `familia` with namespace changes:

| OTS Source | Familia Destination | Changes Required |
|------------|---------------------|------------------|
| `lib/onetime/migration/base_migration.rb` | `lib/familia/migration/base.rb` | Rename `Onetime::Migration::BaseMigration` → `Familia::Migration::Base`; replace `OT.info` → `Familia.logger.info`; replace `Onetime.ld` → configurable Redis |
| `lib/onetime/migration/model_migration.rb` | `lib/familia/migration/model.rb` | Namespace change only |
| `lib/onetime/migration/pipeline_migration.rb` | `lib/familia/migration/pipeline.rb` | Namespace change only |

### 4.2 Extend (Modify Absorbed Code)

Extensions to `Familia::Migration::Base`:

| Addition | Purpose |
|----------|---------|
| `self.migration_id` | Class attribute for unique identifier |
| `self.description` | Class attribute for human-readable description |
| `self.dependencies` | Class attribute for prerequisite migration IDs |
| `#down` | Instance method for rollback logic (optional override) |
| `#reversible?` | Returns true if subclass defines `down` |
| `inherited` hook | Auto-register migrations in global list |

### 4.3 Build New

| Component | Purpose |
|-----------|---------|
| `Familia::Migration::Registry` | Redis-backed tracking of applied migrations |
| `Familia::Migration::Runner` | Discovery, dependency ordering, execution orchestration |
| `Familia::Migration::Script` | Lua script registry for atomic operations |
| `Familia::Migration::Errors` | Migration-specific exception classes |
| Rake tasks | CLI interface for status/run/rollback |

---

## 5. OTS Code Analysis

### 5.1 BaseMigration Capabilities (Reuse As-Is)

The existing `BaseMigration` provides:

**Execution Control**
- `dry_run?` / `actual_run?` — Mode detection
- `for_realsies_this_time? { }` — Execute block only in live mode
- `run_mode_banner` — Display mode warnings

**Statistics**
- `@stats` hash with auto-incrementing counters
- `track_stat(key, increment)` — Named counter management
- `print_summary(title) { }` — Formatted summary output

**Logging**
- `header(message)` — Section headers
- `info`, `debug`, `warn`, `error` — Log levels
- `progress(current, total, message, step)` — Progress at intervals

**Lifecycle**
- `prepare` — Setup hook (optional override)
- `migration_needed?` — Idempotency check (required override)
- `migrate` — Migration logic (required override)

**CLI**
- `self.cli_run(argv)` — Entry point with `--check` and `--run` flags
- `self.check_only` — Exit code for scripting

### 5.2 ModelMigration Capabilities (Reuse As-Is)

Built on `BaseMigration`, adds:

- `@model_class` — Target Horreum subclass
- `@scan_pattern` — Redis key pattern for iteration
- `@batch_size` — Keys per SCAN (default 1000)
- `scan_and_process_records` — SCAN-based iteration
- `process_record(obj, key)` — Per-record hook (required override)
- `load_from_key(key)` — Object hydration from Redis key
- `handle_record_error(key, error)` — Error handling with optional pry

### 5.3 PipelineMigration Capabilities (Reuse As-Is)

Built on `ModelMigration`, adds:

- `process_batch(objects)` — Pipelined batch execution
- `should_process?(obj)` — Filter predicate (required override)
- `build_update_fields(obj)` — Field hash for HMSET (required override)
- `execute_update(pipe, obj, fields, key)` — Custom pipeline ops (optional)
- `process_batch_safely(objects)` — Error-wrapped batch processing

---

## 6. Extensions to BaseMigration

### 6.1 New Class Attributes

```ruby
class Familia::Migration::Base
  class << self
    attr_accessor :migration_id    # String: unique identifier
    attr_accessor :description     # String: human-readable
    attr_accessor :dependencies    # Array<String>: prerequisite IDs
  end
end
```

**Migration ID Format**: `{timestamp}_{snake_case_name}`
Example: `20260131_120000_normalize_emails`

### 6.2 Auto-Registration

```ruby
def self.inherited(subclass)
  super
  subclass.dependencies ||= []
  Familia::Migration.migrations << subclass
end
```

### 6.3 Rollback Support

```ruby
def down
  # Optional: override for rollback logic
end

def reversible?
  method(:down).owner != Familia::Migration::Base
end
```

### 6.4 Logging Adapter

Replace OTS-specific logging with Familia's logger:

```ruby
# OTS uses: OT.info, OT.debug, etc.
# Familia uses: Familia.logger.info, Familia.logger.debug, etc.

def info(msg)
  Familia.logger.info { msg }
end
```

### 6.5 Redis Connection

Replace OTS-specific database access:

```ruby
# OTS uses: Onetime.ld (logical database), specific DB number
# Familia uses: Familia.redis (configurable connection)

def redis
  @redis ||= Familia.redis
end
```

---

## 7. New Component: Registry

Tracks which migrations have been applied using Redis data structures.

### 7.1 Storage Schema

| Key | Type | Content |
|-----|------|---------|
| `{prefix}:applied` | Sorted Set | member=migration_id, score=timestamp |
| `{prefix}:metadata` | Hash | field=migration_id, value=JSON metadata |
| `{prefix}:schema` | Hash | field=model_name, value=schema_digest |
| `{prefix}:backup:{id}` | Hash | field=key:field, value=original_value (TTL: 24h) |

Default prefix: `familia:migrations`

### 7.2 Interface

```ruby
class Familia::Migration::Registry
  def initialize(redis: Familia.redis, prefix: 'familia:migrations')

  # Query
  def applied?(migration_id) → Boolean
  def applied_at(migration_id) → Time | nil
  def all_applied → Array<{migration_id:, applied_at:}>
  def pending(all_migrations) → Array<Class>
  def metadata(migration_id) → Hash | nil
  def status(all_migrations) → Array<Hash>

  # Recording
  def record_applied(migration, stats) → void
  def record_rollback(migration_id) → void

  # Schema tracking
  def schema_digest(model_class) → String (SHA256)
  def store_schema(model_class) → String
  def stored_schema(model_class) → String | nil
  def schema_changed?(model_class) → Boolean
  def schema_drift → Array<Class>

  # Backup
  def backup_field(migration_id, key, field, value) → void
  def restore_backup(migration_id) → Integer (count restored)
  def clear_backup(migration_id) → void
end
```

### 7.3 Metadata Structure

```json
{
  "status": "applied",
  "applied_at": "2026-01-31T12:00:00Z",
  "duration_ms": 1523,
  "keys_scanned": 50000,
  "keys_modified": 15234,
  "errors": 0,
  "reversible": true
}
```

### 7.4 Schema Digest Calculation

```ruby
def schema_digest(model_class)
  fields = model_class.fields.keys.sort
  field_types = fields.map { |f| "#{f}:#{model_class.field_types[f]}" }
  Digest::SHA256.hexdigest(field_types.join('|'))
end
```

Sorted field names ensure deterministic output across Ruby processes.

---

## 8. New Component: Runner

Orchestrates migration discovery, ordering, and execution.

### 8.1 Interface

```ruby
class Familia::Migration::Runner
  def initialize(
    migrations: Familia::Migration.migrations,
    registry: Registry.new,
    logger: Familia.logger
  )

  # Status
  def status → Array<Hash>
  def pending → Array<Class>
  def validate → Array<{type:, message:}>

  # Execution
  def run(dry_run: false, limit: nil) → Array<Result>
  def run_one(migration_class_or_id, dry_run: false) → Result
  def rollback(migration_id) → Result
end
```

### 8.2 Result Structure

```ruby
{
  migration_id: String,
  status: :success | :failed | :rolled_back | :skipped,
  stats: Hash,        # From migration execution
  error: String,      # If failed
  dry_run: Boolean
}
```

### 8.3 Dependency Resolution

Topological sort using Kahn's algorithm:

1. Build graph from `dependencies` arrays
2. Detect cycles (raise `CircularDependency`)
3. Return execution order respecting dependencies

### 8.4 Execution Flow

```
run(dry_run:, limit:)
  │
  ├─→ pending = registry.pending(migrations)
  ├─→ ordered = topological_sort(pending)
  ├─→ ordered = ordered.first(limit) if limit
  │
  └─→ for each migration_class in ordered:
        ├─→ validate_dependencies!(migration_class)
        ├─→ instance = migration_class.new
        ├─→ instance.options[:run] = !dry_run
        ├─→ stats = run via OTS lifecycle (prepare → migrate)
        ├─→ registry.record_applied(instance, stats) unless dry_run
        └─→ break if failed
```

### 8.5 Rollback Flow

```
rollback(migration_id)
  │
  ├─→ Verify: registry.applied?(migration_id)
  ├─→ Verify: no other applied migrations depend on this one
  ├─→ instance = migration_class.new
  ├─→ instance.down
  └─→ registry.record_rollback(migration_id)
```

---

## 9. New Component: Script

Lua script registry for atomic multi-command operations.

### 9.1 Interface

```ruby
class Familia::Migration::Script
  # Class-level registry
  def self.register(name, lua_source) → void
  def self.execute(redis, name, keys:, argv:) → result
  def self.preload_all(redis) → void
end
```

### 9.2 Built-in Scripts

| Name | Purpose | KEYS | ARGV |
|------|---------|------|------|
| `:rename_field` | Atomic hash field rename | [hash_key] | [old_field, new_field] |
| `:copy_field` | Copy field within hash | [hash_key] | [src_field, dst_field] |
| `:delete_field` | Delete hash field | [hash_key] | [field] |
| `:rename_key_preserve_ttl` | Rename key, keep TTL | [src_key, dst_key] | [] |
| `:backup_and_modify_field` | Store old value, set new | [hash_key, backup_key] | [field, new_value, ttl] |

### 9.3 Script: rename_field

```lua
local key = KEYS[1]
local old_field = ARGV[1]
local new_field = ARGV[2]

if redis.call('HEXISTS', key, new_field) == 1 then
  return redis.error_reply('Target field already exists: ' .. new_field)
end

local val = redis.call('HGET', key, old_field)
if val then
  redis.call('HSET', key, new_field, val)
  redis.call('HDEL', key, old_field)
  return 1
end
return 0
```

### 9.4 Script: rename_key_preserve_ttl

```lua
local src = KEYS[1]
local dst = KEYS[2]

if redis.call('EXISTS', dst) == 1 then
  return redis.error_reply('Destination key already exists')
end

local ttl = redis.call('PTTL', src)
redis.call('RENAME', src, dst)

if ttl > 0 then
  redis.call('PEXPIRE', dst, ttl)
end

return ttl
```

---

## 10. New Component: Errors

```ruby
module Familia::Migration::Errors
  class MigrationError < StandardError; end
  class NotReversible < MigrationError; end
  class NotApplied < MigrationError; end
  class NotFound < MigrationError; end
  class DependencyNotMet < MigrationError; end
  class HasDependents < MigrationError; end
  class CircularDependency < MigrationError; end
  class PreconditionFailed < MigrationError; end
end
```

---

## 11. File Structure

```
lib/familia/
  migration.rb                      # Loader + configuration
  migration/
    base.rb                         # ABSORBED from OTS + extensions
    model.rb                        # ABSORBED from OTS (namespace only)
    pipeline.rb                     # ABSORBED from OTS (namespace only)
    registry.rb                     # NEW
    runner.rb                       # NEW
    script.rb                       # NEW
    errors.rb                       # NEW
    rake_tasks.rb                   # NEW
```

---

## 12. Configuration

```ruby
Familia::Migration.configure do |config|
  config.migrations_key = 'familia:migrations'  # Redis key prefix
  config.backup_ttl = 86_400                    # 24 hours
  config.batch_size = 1000                      # Default SCAN batch
end

# Explicit registration (alternative to auto-discovery via inherited)
Familia::Migration.migrations = [
  Migrations::NormalizeEmails,
  Migrations::ConvertTimestamps,
]
```

---

## 13. Rake Tasks

```
familia:migrate           # Run all pending migrations
familia:migrate:status    # Show migration status table
familia:migrate:dry_run   # Preview pending migrations
familia:migrate:rollback[ID]  # Rollback specific migration
familia:migrate:validate  # Check for dependency issues
familia:migrate:schema_drift  # List models with changed schemas
```

### Status Output Format

```
Migration Status:
--------------------------------------------------------------------------------
✓ Applied    20260131_120000_normalize_emails              2026-01-31 12:00
✓ Applied    20260131_130000_add_timestamps                2026-01-31 13:00
○ Pending    20260131_140000_migrate_sessions
--------------------------------------------------------------------------------
Total: 3 (2 applied, 1 pending)
```

---

## 14. Usage Examples

### 14.1 Model Migration (Uses OTS ModelMigration)

```ruby
class NormalizeEmails < Familia::Migration::Model
  self.migration_id = '20260131_120000_normalize_emails'
  self.description = 'Lowercase all email addresses'

  def prepare
    @model_class = Customer
    @batch_size = 500
  end

  def process_record(customer, key)
    return unless customer.email =~ /[A-Z]/

    for_realsies_this_time? do
      customer.email = customer.email.downcase
      customer.save
    end

    track_stat(:emails_normalized)
  end
end
```

### 14.2 Pipeline Migration (Uses OTS PipelineMigration)

```ruby
class AddDefaultSettings < Familia::Migration::Pipeline
  self.migration_id = '20260131_130000_add_default_settings'
  self.description = 'Add default settings field to users'

  def prepare
    @model_class = User
    @batch_size = 100
  end

  def should_process?(user)
    user.settings.nil?
  end

  def build_update_fields(user)
    { 'settings' => '{}' }
  end
end
```

### 14.3 Raw Key Migration (Uses OTS BaseMigration)

```ruby
class CleanupLegacySessions < Familia::Migration::Base
  self.migration_id = '20260131_140000_cleanup_legacy'
  self.description = 'Add TTL to legacy session keys'

  def migration_needed?
    redis.exists('legacy:session:*') > 0
  end

  def migrate
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'legacy:session:*', count: 1000)

      keys.each do |key|
        if redis.ttl(key) == -1
          for_realsies_this_time? { redis.expire(key, 3600) }
          track_stat(:keys_expired)
        end
      end

      break if cursor == '0'
    end
  end

  def down
    # Reversible: remove TTL
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'legacy:session:*', count: 1000)
      keys.each { |key| redis.persist(key) }
      break if cursor == '0'
    end
  end
end
```

### 14.4 Migration with Dependencies

```ruby
class BuildEmailIndex < Familia::Migration::Base
  self.migration_id = '20260131_150000_build_email_index'
  self.dependencies = ['20260131_120000_normalize_emails']  # Must run after

  def migration_needed?
    !redis.exists('idx:customers:by_email')
  end

  def migrate
    # ... build secondary index
  end
end
```

---

## 15. OTS Extraction Checklist

### Phase 1: Copy and Rename

- [ ] Copy `lib/onetime/migration/base_migration.rb` → `lib/familia/migration/base.rb`
- [ ] Copy `lib/onetime/migration/model_migration.rb` → `lib/familia/migration/model.rb`
- [ ] Copy `lib/onetime/migration/pipeline_migration.rb` → `lib/familia/migration/pipeline.rb`
- [ ] Update module namespace: `Onetime::Migration` → `Familia::Migration`
- [ ] Update class names: `BaseMigration` → `Base`, etc.

### Phase 2: Decouple from OTS

- [ ] Replace `OT.info`, `OT.debug`, etc. → `Familia.logger.info`, etc.
- [ ] Replace `Onetime.ld` → `Familia.redis`
- [ ] Remove `require 'onetime'` dependencies
- [ ] Update any OTS-specific model references in examples/comments

### Phase 3: Add Extensions

- [ ] Add `migration_id`, `description`, `dependencies` class attributes
- [ ] Add `inherited` hook for auto-registration
- [ ] Add `down` method stub and `reversible?` predicate
- [ ] Add `redis` accessor method

### Phase 4: Build New Components

- [ ] Implement `Familia::Migration::Registry`
- [ ] Implement `Familia::Migration::Runner`
- [ ] Implement `Familia::Migration::Script`
- [ ] Implement `Familia::Migration::Errors`
- [ ] Implement Rake tasks

### Phase 5: Integration

- [ ] Add `require 'familia/migration'` to main loader
- [ ] Add configuration block support
- [ ] Write tests for new components
- [ ] Update OTS to use `Familia::Migration` instead of `Onetime::Migration`

---

## 16. Backwards Compatibility

OTS applications currently using `Onetime::Migration::BaseMigration` should continue to work after extraction:

```ruby
# Compatibility shim in OTS (temporary)
module Onetime
  module Migration
    BaseMigration = Familia::Migration::Base
    ModelMigration = Familia::Migration::Model
    PipelineMigration = Familia::Migration::Pipeline
  end
end
```

Existing migrations require no changes beyond the namespace (handled by shim).

---

## 17. Open Questions

1. **Auto-discovery**: Should migrations be auto-discovered from a directory, or require explicit registration? Explicit registration is simpler and container-friendly.

2. **OTS coupling**: Should OTS continue to define its own migration subclasses, or move all migrations to Familia patterns?

3. **CLI tool**: Rake tasks vs Thor CLI vs both? Rake is idiomatic for Ruby; Thor matches redis-om's `om` command.

4. **Schema versioning**: Should `schema_version` be a class attribute on Horreum models, triggering warnings on mismatch?

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0-draft | 2026-01-31 | Initial specification |
