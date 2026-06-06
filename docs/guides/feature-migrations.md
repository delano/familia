# Migrations

Redis has no DDL, so Familia migrations operate on live data — renaming keys, reshaping hash fields, backfilling values, adjusting TTLs. The migration system provides idempotent execution, dry-run support, dependency ordering, and a Redis-backed registry that tracks what has run.

## Architecture

```
Base ← Model    (SCAN + per-record callback)
     ← Pipeline (SCAN + batched Redis pipelining)
```

**Base** gives you raw `redis` access for key-level operations. **Model** iterates Horreum objects through `process_record(obj, key)`. **Pipeline** adds `should_process?` / `build_update_fields` for bulk HSET-style updates through Redis pipelines.

All three share the same lifecycle: `prepare` → `migration_needed?` → `migrate` (or `process_record` / pipeline dispatch) → optional `down` for rollback.

## Registry

Applied state lives in Redis, not in files or a relational table:

| Key | Type | Content |
|-----|------|---------|
| `{prefix}:applied` | Sorted Set | migration_id scored by timestamp |
| `{prefix}:metadata` | Hash | migration_id → JSON (duration, keys scanned/modified, reversibility) |
| `{prefix}:schema` | Hash | model_name → SHA256 digest of fields+types |
| `{prefix}:backup:{id}` | Hash (TTL) | field-level rollback data |

Default prefix: `familia:migrations`. The registry answers `applied?`, `pending`, `status`, `schema_changed?`, and `schema_drift` queries.

## Execution model

`Runner` resolves dependencies via topological sort (Kahn's algorithm), then runs pending migrations in order. Each migration is instantiated, prepared, checked with `migration_needed?`, and executed. The registry is updated only on non-dry-run success.

Rollback validates three preconditions: the migration is applied, no dependents are applied, and the migration implements `down`.

## Dry-run control

`for_realsies_this_time? { ... }` gates destructive operations. In dry-run mode the block is skipped and the registry is not updated. `dry_run_only? { ... }` provides the inverse gate for preview-only logging.

## Lua scripts

`Familia::Migration::Script` provides atomic Redis operations for common migration patterns: `rename_field`, `copy_field`, `delete_field`, `rename_key_preserve_ttl`, `backup_and_modify_field`. Custom scripts can be registered and executed through the same interface.

## Source files

`lib/familia/migration.rb` and `lib/familia/migration/`. Each file's first line states its purpose.