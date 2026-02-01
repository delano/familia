# Writing Migrations

## Quick Start

Minimal working migration:

```ruby
class NormalizeEmails < Familia::Migration::Base
  self.migration_id = '20260131_120000_normalize_emails'
  self.description = 'Lowercase all email addresses'

  def migration_needed?
    redis.exists('needs:normalization') > 0
  end

  def migrate
    redis.scan_each(match: 'user:*:object') do |key|
      for_realsies_this_time? do
        # perform changes
      end
      track_stat(:processed)
    end
  end
end
```

Run it:

```bash
bundle exec rake familia:migrate:dry_run    # Preview
bundle exec rake familia:migrate            # Apply
```

## Migration Types

| Type | Use When | Key Method |
|------|----------|------------|
| `Base` | Raw Redis operations, key patterns, config changes | `migrate` |
| `Model` | Iterating over Horreum objects with per-record logic | `process_record(obj, key)` |
| `Pipeline` | Bulk updates with Redis pipelining (1000+ records) | `should_process?(obj)`, `build_update_fields(obj)` |

### Base

Direct Redis access. Use for key renames, TTL changes, config migrations:

```ruby
class AddTTLToSessions < Familia::Migration::Base
  self.migration_id = '20260131_add_ttl'

  def migration_needed?
    redis.exists('legacy:session:*') > 0
  end

  def migrate
    cursor = '0'
    loop do
      cursor, keys = redis.scan(cursor, match: 'legacy:session:*', count: 1000)
      keys.each do |key|
        for_realsies_this_time? { redis.expire(key, 3600) }
        track_stat(:keys_expired)
      end
      break if cursor == '0'
    end
  end
end
```

### Model

SCAN-based iteration over Horreum objects. Use for per-record transformations with error handling:

```ruby
class CustomerEmailMigration < Familia::Migration::Model
  self.migration_id = '20260131_customer_emails'

  def prepare
    @model_class = Customer
    @batch_size = 500  # optional, default: 1000
  end

  def process_record(customer, key)
    return unless customer.email =~ /[A-Z]/

    for_realsies_this_time? do
      customer.email = customer.email.downcase
      customer.save
    end
    track_stat(:records_updated)
  end
end
```

### Pipeline

Batched updates using Redis pipelining. Use for high-volume simple field updates:

```ruby
class AddDefaultSettings < Familia::Migration::Pipeline
  self.migration_id = '20260131_default_settings'

  def prepare
    @model_class = User
    @batch_size = 100  # smaller batches for pipelines
  end

  def should_process?(user)
    user.settings.nil?
  end

  def build_update_fields(user)
    { 'settings' => '{}' }
  end
end
```

Override `execute_update` for custom pipeline operations:

```ruby
def execute_update(pipe, obj, fields, original_key)
  dbkey = original_key || obj.dbkey
  pipe.hmset(dbkey, *fields.flatten)
  pipe.expire(dbkey, 86400)  # also set TTL
end
```

## Class Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `migration_id` | Yes | Unique identifier. Format: `YYYYMMDD_HHMMSS_snake_case_name` |
| `description` | No | Human-readable summary for status output |
| `dependencies` | No | Array of migration IDs that must run first |

```ruby
class BuildEmailIndex < Familia::Migration::Base
  self.migration_id = '20260131_150000_build_index'
  self.description = 'Create secondary index for email lookups'
  self.dependencies = ['20260131_120000_normalize_emails']
  # ...
end
```

## Lifecycle Methods

| Method | Purpose | Required |
|--------|---------|----------|
| `prepare` | Initialize config, set `@model_class` | Model/Pipeline only |
| `migration_needed?` | Idempotency check. Return `false` to skip. | Yes |
| `migrate` | Core migration logic | Base only |
| `process_record(obj, key)` | Per-record logic | Model only |
| `should_process?(obj)` | Filter predicate | Pipeline only |
| `build_update_fields(obj)` | Return Hash of field updates | Pipeline only |
| `down` | Rollback logic | No (enables rollback) |

## Dry Run vs Live

Wrap destructive operations with `for_realsies_this_time?`:

```ruby
def migrate
  redis.scan_each(match: 'session:*') do |key|
    for_realsies_this_time? do
      redis.del(key)  # only executes with --run
    end
    track_stat(:deleted)
  end
end
```

| Mode | `for_realsies_this_time?` | Registry Updated |
|------|---------------------------|------------------|
| Dry run (`:dry_run` task) | Block skipped | No |
| Live (`:run` task) | Block executes | Yes |

## Dependencies

Dependencies ensure execution order. The runner uses topological sort (Kahn's algorithm).

```ruby
class MigrationA < Familia::Migration::Base
  self.migration_id = 'step_a'
  self.dependencies = []
end

class MigrationB < Familia::Migration::Base
  self.migration_id = 'step_b'
  self.dependencies = ['step_a']  # runs after step_a
end
```

Rollback is blocked if dependents are still applied:

```ruby
runner.rollback('step_a')
# => Errors::HasDependents if step_b is applied
```

## Rollback

Implement `down` to enable rollback:

```ruby
class AddFeatureFlag < Familia::Migration::Base
  self.migration_id = '20260131_feature_flag'

  def migration_needed?
    !redis.exists?('config:feature:enabled')
  end

  def migrate
    for_realsies_this_time? do
      redis.set('config:feature:enabled', 'true')
    end
  end

  def down
    redis.del('config:feature:enabled')
  end
end
```

Check reversibility:

```ruby
instance = AddFeatureFlag.new
instance.reversible?  # => true
```

## Lua Scripts

Use `Familia::Migration::Script` for atomic operations:

```ruby
# Rename hash field atomically
Familia::Migration::Script.execute(
  redis,
  :rename_field,
  keys: ['user:123:object'],
  argv: ['old_name', 'new_name']
)
```

Built-in scripts:

| Script | Purpose | KEYS | ARGV |
|--------|---------|------|------|
| `:rename_field` | Rename hash field | `[hash_key]` | `[old, new]` |
| `:copy_field` | Copy field within hash | `[hash_key]` | `[src, dst]` |
| `:delete_field` | Delete hash field | `[hash_key]` | `[field]` |
| `:rename_key_preserve_ttl` | Rename key, keep TTL | `[src, dst]` | `[]` |
| `:backup_and_modify_field` | Backup old value, set new | `[hash, backup]` | `[field, value, ttl]` |

Register custom scripts:

```ruby
Familia::Migration::Script.register(:my_script, <<~LUA)
  local key = KEYS[1]
  return redis.call('GET', key)
LUA
```

## CLI Reference

```bash
# Status
bundle exec rake familia:migrate:status       # Show applied/pending
bundle exec rake familia:migrate:validate     # Check dependency issues
bundle exec rake familia:migrate:schema_drift # Models with changed schemas

# Execution
bundle exec rake familia:migrate:dry_run      # Preview (no changes)
bundle exec rake familia:migrate              # Apply all pending
bundle exec rake familia:migrate:run          # Same as above

# Rollback
bundle exec rake "familia:migrate:rollback[20260131_120000_migration_id]"
```

## Statistics

Track operations with `track_stat`:

```ruby
def process_record(obj, key)
  if obj.email.blank?
    track_stat(:skipped_blank)
    return
  end

  for_realsies_this_time? do
    obj.email = obj.email.downcase
    obj.save
  end
  track_stat(:records_updated)
end
```

Access stats:

```ruby
instance.stats[:records_updated]  # => 42
instance.stats[:skipped_blank]    # => 7
```

## Configuration

```ruby
Familia::Migration.configure do |config|
  config.migrations_key = 'familia:migrations'  # Registry key prefix
  config.backup_ttl = 86_400                    # Backup expiration (24h)
  config.batch_size = 1000                      # Default SCAN batch
end
```

## Best Practices

1. **Test locally first.** Run dry run, verify stats, then run live on staging before production.

2. **Deploy schema changes separately.** Avoid updating model definitions and running migrations in the same deploy. New model logic can break migration code.

3. **Keep migrations idempotent.** `migration_needed?` should return `false` after successful execution.

4. **Use descriptive IDs.** `20260131_120000_normalize_customer_emails` beats `20260131_fix_stuff`.

5. **Backup critical data.** Use `:backup_and_modify_field` or `registry.backup_field` before destructive changes.

## Error Reference

| Error | Cause |
|-------|-------|
| `NotReversible` | `down` not implemented |
| `NotApplied` | Rollback of unapplied migration |
| `DependencyNotMet` | Dependency not yet applied |
| `HasDependents` | Rollback blocked by dependents |
| `CircularDependency` | Dependency cycle detected |
| `PreconditionFailed` | `@model_class` not set in `prepare` |

## Source Files

- [`lib/familia/migration/base.rb`](../../lib/familia/migration/base.rb)
- [`lib/familia/migration/model.rb`](../../lib/familia/migration/model.rb)
- [`lib/familia/migration/pipeline.rb`](../../lib/familia/migration/pipeline.rb)
- [`lib/familia/migration/registry.rb`](../../lib/familia/migration/registry.rb)
- [`lib/familia/migration/runner.rb`](../../lib/familia/migration/runner.rb)
- [`lib/familia/migration/script.rb`](../../lib/familia/migration/script.rb)
