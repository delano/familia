Added
-----

- Redis-native migration system with three patterns: Base (abstract foundation),
  Model (record-by-record iteration via SCAN), and Pipeline (bulk updates with
  Redis pipelining). Includes dependency resolution using topological sort,
  dry-run mode, CLI support, and comprehensive Rake tasks.

- Migration registry for tracking applied migrations in Redis with rollback
  support and schema drift detection.

- Lua script framework with atomic operations: rename_field, copy_field,
  delete_field, rename_key_preserve_ttl, and backup_and_modify_field.

- Optional JSON Schema validation for Horreum models via ``feature :schema_validation``
  with centralized SchemaRegistry supporting convention-based and explicit schema
  discovery using the json_schemer gem.

- V1 to V2 serialization migration example at ``examples/migrations/v1_to_v2_serialization_migration.rb``
  demonstrating how to upgrade Horreum objects from v1.x format (selective serialization
  with type information loss) to v2.0 format (universal JSON encoding with type preservation).
  Includes type detection heuristics, field type declarations, and batch processing.

Documentation
-------------

- Added comprehensive migration writing guide at ``docs/guides/writing-migrations.md``
  covering all three migration patterns, CLI usage, dependencies, and best practices.

AI Assistance
-------------

- Claude Code assisted with test coverage analysis, identifying gaps in Model and
  Pipeline test coverage. Implemented 67 new tests covering CLI entry points,
  circular dependency detection, and comprehensive Model/Pipeline scenarios.

- Claude Code identified and fixed a bug where schema validation hooks were never
  triggered in Model migrations, and optimized N+1 query patterns in Registry and
  Runner classes.
