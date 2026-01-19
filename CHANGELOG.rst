CHANGELOG.rst
=============

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-2.0.0.pre26:

2.0.0.pre26 — 2026-01-19
========================

Fixed
-----

- Fixed relationship reverse lookup methods failing when a class declares an explicit
  ``prefix`` that differs from its computed ``config_name``. For example, a class with
  ``prefix :customdomain`` (no underscore) but ``config_name`` returning ``"custom_domain"``
  (with underscore) now correctly finds related instances. PR #207

AI Assistance
-------------

- Claude Opus 4.5 assisted with root cause analysis, coordinating multiple agents to
  explore the codebase, implementing the fix across 5 locations, and writing comprehensive
  test coverage (53 test cases) for various prefix/config_name scenarios.

.. _changelog-2.0.0.pre25:

2.0.0.pre25 — 2026-01-08
========================

Added
-----

- Class-level multi-value indexing with ``multi_index :field, :index_name`` (``within: :class`` is now the default). Creates class methods like ``Model.find_all_by_field(value)`` and ``Model.sample_from_field(value, count)`` for grouping objects by field values at the class level.

- New ``JsonStringKey`` DataType for type-preserving string storage. Unlike
  ``StringKey`` which uses raw strings (for INCR/DECR support), ``JsonStringKey``
  uses JSON serialization to preserve Ruby types (Integer, Float, Boolean, Hash,
  Array) across the Redis storage boundary. Registered as ``:json_string`` and
  ``:json_stringkey``, enabling DSL methods like ``json_string :metadata`` and
  ``class_json_string :last_synced_at``.

Changed
-------

- ``multi_index`` now defaults to ``within: :class`` instead of requiring a scope class. Existing instance-scoped indexes (``within: SomeClass``) continue to work unchanged.

Removed
-------

- **BREAKING**: Removed ``dump_method`` and ``load_method`` configuration options
  from ``Familia::Base``, ``Familia::Horreum``, and ``Familia::DataType``. JSON
  serialization via ``to_json``/``from_json`` is now hard-coded for consistency
  and type safety. Custom serialization methods are no longer supported.

AI Assistance
-------------

- Claude Opus 4.5 assisted with design, implementation, and testing of serialization consistency, the JsonStringKey feature, and multi_index :class mode.
- Gemini 3 Flash assisted with editing and trimming this section.


.. _changelog-2.0.0.pre24:

2.0.0.pre24 — 2026-01-07
========================

Added
-----

- Add comprehensive test coverage for ``find_by_dbkey`` race condition and lazy cleanup
  scenarios in ``try/edge_cases/find_by_dbkey_race_condition_try.rb`` (16 new tests).
  Tests cover empty hash handling, lazy cleanup, TTL expiration, count consistency,
  and concurrent access patterns.

Fixed
-----

- Fix race condition in ``find_by_dbkey`` where keys expiring between EXISTS and HGETALL
  could create objects with nil identifiers, causing ``NoIdentifier`` errors on subsequent
  operations like ``destroy!``. Now always checks for empty hash results regardless of
  ``check_exists`` parameter value.

- Add lazy cleanup of stale ``instances`` sorted set entries when ``find_by_dbkey`` detects
  a non-existent key (via EXISTS check) or an expired key (via empty HGETALL result). This
  prevents phantom instance counts from accumulating when objects expire via TTL without
  explicit ``destroy!`` calls. The cleanup is performed opportunistically during load
  attempts, requiring no background jobs or Redis keyspace notifications.

AI Assistance
-------------

- Claude helped verify the race condition analysis through multi-agent investigation
  (Explore, Code Explorer, QA Engineer agents) and implemented the fix with lazy cleanup
  and comprehensive test coverage.

.. _changelog-2.0.0.pre23:

2.0.0.pre23 — 2025-12-22
========================

Added
-----

- Add ``:through`` option to ``participates_in`` for join model support.
  Enables storing additional attributes (role, permissions, metadata) on
  participation relationships via an intermediate model. The through model
  uses deterministic keys and supports idempotent operations - adding an
  existing participant updates rather than duplicates.

Security
--------

- Add validation for through model attributes to prevent arbitrary method
  invocation. Only fields defined on the through model schema can be set
  via the ``through_attrs`` parameter.

Documentation
-------------

- Add YARD documentation for the ``:through`` parameter on both
  ``participates_in`` and ``class_participates_in`` methods.

AI Assistance
-------------

- Implementation design and code review assistance provided by Claude.
  Security hardening for attribute validation added based on Qodo review.

.. _changelog-2.0.0.pre22:

2.0.0.pre22 — 2025-12-03
========================

- **ExternalIdentifier Format Flexibility**: The `external_identifier` feature now supports customizable format templates via the `format` option (e.g., `format: 'cust_%{id}'` or `format: 'api-%{id}'`). Default format remains `'ext_%{id}'`. Provides complete flexibility for various ID formatting needs including different prefixes, separators, URL paths, or no prefix at all.

- **Participation Relationships with Symbol/String Target Classes**: Fixed four bugs that occurred when calling `participates_in` with Symbol/String target class instead of Class object. Issues included NoMethodError during relationship definition (private method call), failures in `current_participations` (undefined `familia_name`), errors in `target_class_config_name` (undefined `config_name`), and confusing error messages for load order issues. All now properly resolve using `Familia.resolve_class` API with clear error messages for common issues.

- **Pipelined Bulk Loading Methods**: New `load_multi` and `load_multi_by_keys` methods enable efficient bulk object loading using Redis pipelining, reducing network round trips from N×2 commands to a single batch (up to 2× performance improvement). Methods maintain nil-return contract for missing objects and preserve input order.

- **Optional EXISTS Check Optimization**: The `find_by_dbkey` and `find_by_identifier` methods now accept `check_exists:` parameter (default: `true`) to optionally skip EXISTS check, reducing Redis commands from 2 to 1 per object. Maintains backwards compatibility and same nil-return behavior.

- **Parameter Consistency**: The `suffix` parameter in `find_by_identifier` is now a keyword parameter (was optional positional) for consistency with `check_exists`, following Ruby conventions.

Added
-----

- Bidirectional reverse collection methods for ``participates_in`` with ``_instances`` suffix (e.g., ``user.project_team_instances``, ``user.project_team_ids``). Supports union behavior for multiple collections and custom naming via ``as:`` parameter. Closes #179.

Changed
-------

- All Ruby files now include consistent headers with ``frozen_string_literal: true`` pragma for improved performance and memory efficiency. Headers follow the format: filename comment, blank comment line, frozen string literal pragma. Executable scripts properly place shebang first.

- Standardized DataType serialization to use JSON encoding for type preservation, matching Horreum field behavior. All primitive values (Integer, Boolean, String, Float, Hash, Array, nil) are now consistently serialized through JSON, ensuring types are preserved across the Redis storage boundary. Familia object references continue to use identifier extraction. Issue #190.

Fixed
-----

- Fixed critical race condition in mutex initialization for connection chain lazy loading. The mutex itself was being lazily initialized with ``||=``, which is not atomic and could result in multiple threads creating different mutex instances, defeating synchronization. Changed to eager initialization via ``Connection.included`` hook. (`lib/familia/horreum/connection.rb`)

- Fixed critical race condition in mutex initialization for logger lazy loading. Similar to connection chain issue, the logger mutex was lazily initialized with ``||=``. Changed to eager initialization at module definition time. (`lib/familia/logging.rb`)

- Fixed logger assignment atomicity issue where ``Familia.logger=`` set ``DatabaseLogger.logger`` outside the mutex synchronization block, potentially causing ``Familia.logger`` and ``DatabaseLogger.logger`` to be temporarily out of sync during concurrent access. Moved ``DatabaseLogger.logger`` assignment inside the synchronization block. (`lib/familia/logging.rb`)

- Added explicit return statement to ``Familia.logger`` method for robustness against future refactoring. (`lib/familia/logging.rb`)

AI Assistance
-------------

- Claude Code (Opus 4, Sonnet 4.5): Implementation of bidirectional participation relationships, external identifier format flexibility, bulk loading optimization with pipelining, race condition fixes in mutex initialization, frozen string literal pragma automation (308 files), and DataType serialization standardization. Comprehensive test coverage and documentation throughout.

.. _changelog-2.0.0.pre21:

2.0.0.pre21 — 2025-10-21
========================

Added
-----

- Pipeline Routing Investigation: Created 7 diagnostic testcases in ``try/investigation/pipeline_routing/`` to investigate suspected middleware routing issue. Investigation revealed single-command pipelines don't have ' | ' separator (expected Array#join behavior), confirming no routing bug exists. Full analysis documented in ``CONCLUSION.md``.

Changed
-------

- **BREAKING**: Duration measurements now use integer microseconds instead of milliseconds. Instrumentation hooks and logging output have changed format:

  - ``Familia.on_command`` receives ``duration`` in microseconds (was ``duration_ms`` in milliseconds)
  - ``Familia.on_pipeline`` receives ``duration`` in microseconds (was ``duration_ms`` in milliseconds)
  - ``Familia.on_lifecycle`` uses ``duration`` key in microseconds (was ``duration_ms`` in milliseconds)
  - Log messages show ``duration=1234`` (microseconds) instead of ``duration_ms=1.23`` (milliseconds)

- Migration: Convert to milliseconds when needed: ``duration / 1000.0``

Fixed
-----

- Connection Chain Race Condition: Fixed race condition in connection chain initialization where concurrent calls could create multiple instances. Added thread-safe protection to ensure proper singleton behavior.

- Thread Safety Test Suite: Corrected test assertions to properly verify thread safety invariants.


AI Assistance
-------------

- Claude Code assisted with analyzing test failures, identifying and fixing the connection chain race condition with Mutex protection, correcting test assertions to verify proper thread safety invariants, and creating diagnostic testcases to investigate pipeline routing behavior.



.. _changelog-2.0.0.pre20:

2.0.0.pre20 — 2025-10-20
========================

Added
-----

- **Instrumentation Hooks**: New ``Familia::Instrumentation`` module provides hooks for Redis commands, pipeline operations, lifecycle events, and errors. Applications can now register callbacks for audit trails and performance monitoring.

- **DatabaseLogger Structured Mode**: Added ``DatabaseLogger.structured_logging`` mode that outputs Redis commands with structured key=value context instead of formatted string output.

- **DatabaseLogger Sampling**: Added ``DatabaseLogger.sample_rate`` for controlling log volume in high-traffic scenarios. Set to 0.1 for 10% sampling, 0.01 for 1% sampling, or nil to disable. Command capture for testing remains unaffected.

- **Lifecycle Logging**: Horreum initialize, save, and destroy operations now log with timing and structured context when ``FAMILIA_DEBUG`` is enabled.

- **Operational Logging**: TTL operations and serialization errors now include structured context for better debugging.

Changed
-------

- Refactored ``save`` and ``save_if_not_exists!`` to use shared helper methods (``prepare_for_save`` and ``persist_to_storage``) to eliminate code duplication and ensure consistency. Both methods now follow the same preparation and persistence logic, differing only in their concurrency control patterns (simple transaction vs. optimistic locking with WATCH).

- **Structured Logging**: Replaced internal logging methods (``Familia.ld``, ``Familia.le``) with structured logging methods (``Familia.debug``, ``Familia.info``, ``Familia.error``) that support keyword context for operational observability.

Removed
-------

- **Internal Methods**: Removed ``Familia.ld`` and ``Familia.le`` internal logging methods. These were never part of the public API.

Fixed
-----

- Fixed ``save_if_not_exists!`` to perform the same operations as ``save`` when creating new objects. Previously, ``save_if_not_exists!`` omitted timestamp updates (``created``/``updated``), unique index validation (``guard_unique_indexes!``), and adding to the instances collection. Now both methods produce identical results when saving a new object, with ``save_if_not_exists`` only differing in its conditional existence check.

- Fixed ``save_if_not_exists!`` return value to correctly return ``true`` when successfully saving new objects. Previously returned ``false`` despite successful persistence due to incorrect handling of transaction result.

Documentation
-------------

- Streamlined inline documentation for ``save``, ``save_if_not_exists!``, and ``save_if_not_exists`` methods to be more concise, internally consistent, and non-redundant. Each method's documentation now stands on its own with clear, focused descriptions.

AI Assistance
-------------

- Claude Code identified the inconsistencies between ``save`` and ``save_if_not_exists!`` methods, implemented the fixes, refactored both methods to extract shared logic into private helper methods (``prepare_for_save`` and ``persist_to_storage``), and updated the documentation to be more concise and internally consistent.



This implementation was completed with significant AI assistance from Claude (Anthropic), including:

- Architecture design for the instrumentation hook system
- Implementation of structured logging methods with backward-compatible signatures
- Integration of hooks into DatabaseLogger middleware
- Bulk replacement of 51 logging method calls across 21 files
- Comprehensive code review and bug fixes (RedisClient::Config object vs hash handling)
- Documentation and changelog creation

The AI provided discussion, rubber ducking, code generation, testing strategy, and documentation throughout the implementation process.

Developer Notes
---------------

This is a clean break for v2.0 with no deprecation warnings, as the removed methods were internal-only. Applications using the public API are unaffected.

**Migration**: No action required for external users. Internal development references to ``Familia.ld`` should use ``Familia.debug``, and ``Familia.le`` should use ``Familia.error``.

**New Capabilities**: Applications can now register instrumentation hooks for operational observability:

.. code-block:: ruby

   # Enable structured logging with 10% sampling for production
   Familia.logger = Rails.logger
   DatabaseLogger.structured_logging = true
   DatabaseLogger.sample_rate = 0.1  # Log 10% of commands

   # Register hooks for audit trails
   Familia.on_command do |cmd, duration_ms, context|
     AuditLog.create!(
       event: 'redis_command',
       command: cmd,
       duration_ms: duration_ms,
       user_id: RequestContext.current_user_id
     )
   end

   Familia.on_lifecycle do |event, instance, context|
     case event
     when :save
       AuditLog.create!(event: 'object_saved', object_id: instance.identifier)
     when :destroy
       AuditLog.create!(event: 'object_destroyed', object_id: instance.identifier)
     end
   end

.. _changelog-2.0.0.pre19:

2.0.0.pre19 — 2025-10-13
========================

Added
-----

-  **DataType Transaction and Pipeline Support** - DataType objects can now initiate transactions and pipelines independently, enabling atomic operations and batch command execution. `PR #159 <https://github.com/familia/familia/pull/159>`_

   * ``transaction`` and ``pipelined`` methods for all DataType classes
   * Connection chain pattern with ``ParentDelegationHandler`` and ``StandaloneConnectionHandler``
   * Enhanced ``direct_access`` method with automatic context detection
   * Shared ``Familia::Connection::Behavior`` module for common functionality

-  **Automatic Unique Index Validation** - Instance-scoped unique indexes now validate automatically in ``add_to_*`` methods, with transaction detection to prevent ``save()`` calls within MULTI/EXEC blocks

Changed
-------

-  **Connection Architecture** - Refactored to share ``Familia::Connection::Behavior`` between Horreum and DataType, with cleaner URI construction for logical databases

-  **Indexing Terminology** - Renamed internal ``target_class`` to ``scope_class`` throughout to clarify semantic role. Added explicit ``:within`` field to IndexingRelationship for clearer instance-scoped index handling

Fixed
-----

-  URI formatting for DataType objects with logical database settings
-  Transaction detection and validation flow for unique index operations

Documentation
-------------

-  Enhanced ``save()`` method documentation with transaction restrictions
-  Updated indexing and relationship cheatsheets with improved terminology
-  Added comprehensive test coverage (48 new tests) for transactions, pipelines, and validation

AI Assistance
-------------

This release was implemented with assistance from Claude (Anthropic) for architectural design, test coverage, and systematic refactoring of terminology across the codebase.


.. _changelog-2.0.0.pre18:

2.0.0.pre18 — 2025-10-05
========================

Added
-----

- Added ``Familia.reconnect!`` method to refresh connection pools with current middleware configuration. This solves issues in test suites where middleware (like DatabaseLogger) is enabled after connection pools are created. The method clears the connection chain, increments the middleware version, and clears fiber-local connections, ensuring new connections include the latest middleware. See ``lib/familia/connection/middleware.rb:81-117``.

Changed
-------

- **BREAKING**: Implemented type-preserving JSON serialization for Horreum field values. Non-string values (Integer, Boolean, Float, nil, Hash, Array) are JSON-encoded for storage and JSON-decoded on retrieval. **Strings are stored as-is without JSON encoding** to avoid double-quoting and maintain Redis baseline simplicity. Type preservation is achieved through smart deserialization: values that parse as JSON restore to their original types, otherwise remain as strings.

- **BREAKING**: Changed default Hash key format from symbols to strings throughout the codebase (``symbolize: false`` default). This eliminates ambiguity with HTTP request parameters and IndifferentHash-style implementations, providing strict adherence to JSON parsing rules and avoiding key duplication issues.

- **BREAKING**: Fixed ``initialize_with_keyword_args`` to properly handle ``false`` and ``0`` values during object initialization. Previously, falsy values were incorrectly skipped due to truthiness checks. Now uses explicit nil checking with ``fetch`` to preserve all non-nil values including ``false`` and ``0``.

- **String serialization now uses JSON encoding**: All string values are JSON-encoded during storage (wrapped in quotes) for consistent type preservation. The lenient deserializer handles both new JSON-encoded strings and legacy plain strings automatically. PR #152

Removed
-------

- **BREAKING**: Removed ``dump_method`` and ``load_method`` configuration options from ``Familia::Base`` and ``Familia::Horreum::Definition``. JSON serialization is now hard-coded for consistency and type safety. Custom serialization methods are no longer supported.

Fixed
-----

- Fixed type coercion bugs where Integer fields (e.g., ``age: 35``) became Strings (``"35"``) and Boolean fields (e.g., ``active: true``) became Strings (``"true"``) after database round-trips. All primitive types now maintain their original types through ``find_by_dbkey``, ``refresh!``, and ``batch_update`` operations.

- Fixed ``deserialize_value`` to return all JSON-parsed types instead of filtering to Hash/Array only. This enables proper deserialization of primitive types (Integer, Boolean, Float, String) from Redis storage.

- Added JSON deserialization in ``find_by_dbkey`` using existing ``initialize_with_keyword_args_deserialize_value`` helper method to maintain DRY principles and ensure loaded objects receive properly typed field values rather than raw Redis strings.

- Optimized serialization to avoid double-encoding strings - strings stored directly in Redis as-is, only non-string types use JSON encoding. This reduces storage overhead and maintains Redis's string baseline semantics.

- Fixed encrypted fields with ``category: :encrypted`` appearing in ``to_h()`` output. These fields now correctly set ``loggable: false`` to prevent accidental exposure in logs, APIs, or external interfaces. PR #152

- Fixed middleware registration to only set ``@middleware_registered`` flag when middleware is actually enabled and registered. Previously, calling ``create_dbclient`` before enabling middleware would set the flag to ``true`` without registering anything, preventing later middleware enablement from working. The fix ensures ``register_middleware_once`` only sets the flag after successful registration. See ``lib/familia/connection/middleware.rb:124-146``.

Security
--------

- Encrypted fields defined via ``field :name, category: :encrypted`` now properly excluded from ``to_h()`` serialization, matching the security behavior of ``encrypted_field``. PR #152

Documentation
-------------

- Added comprehensive type preservation test suite (``try/unit/horreum/json_type_preservation_try.rb``) with 30 test cases covering Integer, Boolean, String, Float, Hash, Array, nested structures, nil handling, empty strings, zero values, round-trip consistency, ``batch_update``, and ``refresh!`` operations.

AI Assistance
-------------

- Claude Code (claude-sonnet-4-5) provided implementation guidance, identified the ``initialize_with_keyword_args`` falsy value bug, wrote test coverage, and coordinated multi-file changes across serialization, management, and base modules.

- Issue analysis, implementation guidance, test verification, and documentation for JSON serialization changes and encrypted field security fix.

- Claude Code (Sonnet 4.5) provided architecture analysis, implementation design, and identified critical issues through the second-opinion agent. Key contributions included recommending the simplified approach without pool shutdown lifecycle management, identifying the race condition risk in clearing ``@middleware_registered``, and suggesting the use of natural pool aging instead of explicit shutdown.

.. _changelog-2.0.0.pre17:

2.0.0.pre17 — 2025-10-03
========================

Added
-----

- **SortedSet#add** - Full ZADD option support (NX, XX, GT, LT, CH) for atomic conditional operations and accurate change tracking. Closes #135

Fixed
-----

- Restored objid provenance tracking when loading objects from Redis, enabling dependent features to derive external identifiers. PR #131

AI Assistance
-------------

- Claude (Anthropic) assisted with objid generator inference implementation and ZADD option validation design.

.. _changelog-2.0.0.pre16:

2.0.0.pre16 — 2025-09-30
========================

Added
-----

- **Instance-scoped unique indexes** via ``unique_index`` with ``within:`` parameter for per-scope unique lookups. Issue #128

Changed
-------

- **BREAKING**: Consolidated relationships API - replaced ``tracked_in`` and ``member_of`` with unified ``participates_in`` method. PR #110

- **BREAKING**: Renamed indexing API methods for clarity. Issue #128
  - ``class_indexed_by`` → ``unique_index``
  - ``indexed_by`` → ``multi_index``
  - Changed ``multi_index`` to use ``UnsortedSet`` instead of ``SortedSet``

- **DataType class renaming** to avoid Ruby namespace conflicts: ``Familia::String`` → ``Familia::StringKey``, ``Familia::List`` → ``Familia::ListKey``, etc., with dual registration for compatibility

Documentation
-------------

- Updated indexing and participation module documentation with comprehensive examples and design philosophy

AI Assistance
-------------

- Claude (Anthropic) assisted with relationship API consolidation, DataType renaming, and indexing API refactoring.

.. _changelog-2.0.0.pre14:

2.0.0.pre14 — 2025-09-08
========================

Changed
-------

- **BREAKING**: Renamed ``TimeUtils`` to ``TimeLiterals`` to better reflect module purpose. PR #100

Fixed
-----

- **CRITICAL**: Fixed Redis connection persistence for standalone DataType objects. PR #107
- Fixed ExternalIdentifier HashKey cleanup using correct ``remove_field()`` method. PR #100

AI Assistance
-------------

- Claude (Anthropic) and Gemini assisted with TimeLiterals refactoring and ExternalIdentifier fixes.

.. _changelog-2.0.0.pre13:

2.0.0.pre13 — 2025-09-07
========================

Added
-----

- **Feature Autoloading System** - Features automatically discover and load extension files from project directories using conventional patterns. PR #97

- **Month calculations** - Added ``PER_MONTH`` constant and month conversion methods to TimeLiterals refinement. Issue #94

Changed
-------

- **Performance** - Replaced stdlib JSON with OJ gem for 2-5x faster operations. PR #97
- Refactored time/numeric extensions from global monkey patches to Ruby refinements
- Enhanced encryption serialization safety with improved ConcealedString handling

Fixed
-----

- Fixed ``months_old`` and ``years_old`` methods returning raw seconds instead of proper units. Issue #94
- Fixed byte conversion boundary logic (``size >= 1024`` instead of ``size > 1024``)
- Fixed calendar consistency where ``12.months != 1.year`` by using Gregorian year

Security
--------

- Improved concealed value protection during JSON serialization across all OJ modes. PR #97

Documentation
-------------

- Added Feature System Autoloading guide with conventions and usage examples
- Enhanced YARD documentation for autoloading modules

AI Assistance
-------------

- Claude (Anthropic) assisted with refinement refactoring, autoloading system design, and OJ integration.

2.0.0.pre12 — 2025-09-04
========================

Added
~~~~~

-  Added the ``Familia::VerifiableIdentifier`` module to create and
   verify identifiers with an embedded HMAC signature. This allows an
   application to stateless-ly confirm that an identifier was generated
   by itself, preventing forged IDs from malicious sources.

-  **Scoped VerifiableIdentifier**: Added ``scope`` parameter to
   ``generate_verifiable_id()`` and ``verified_identifier?()`` methods,
   enabling cryptographically isolated identifier namespaces for
   multi-tenant, multi-domain, or multi-environment applications while
   maintaining full backward compatibility with existing code.

Changed
~~~~~~~

-  ObjectIdentifier feature now tracks which generator (uuid_v7,
   uuid_v4, hex, or custom) was used for each objid to provide
   provenance information for security-sensitive operations.

-  Updated external identifier derivation to normalize objid format
   based on the known generator type, eliminating format ambiguity
   between UUID and hex formats.

-  Refactored identifier generation methods for clarity and consistency.
   Method ``generate_objid`` is now ``generate_object_identifier``, and
   ``generate_external_identifier`` is now
   ``derive_external_identifier`` to reflect its deterministic nature.

Removed
~~~~~~~

-  Removed the ``generate_extid`` class method, which was less secure
   than the instance-level derivation logic.

Security
~~~~~~~~

-  Hardened external identifier derivation with provenance validation.
   ExternalIdentifier now validates that objid values come from the
   ObjectIdentifier feature before deriving external identifiers,
   preventing derivation from potentially malicious or unvalidated objid
   values while maintaining deterministic behavior for legitimate use
   cases.

-  Improved the security of external identifiers (``extid``) by using
   the internal object identifier (``objid``) as a seed for a new random
   value, rather than deriving the ``extid`` directly. This prevents
   potential information leakage from the internal ``objid``.

Documentation
~~~~~~~~~~~~~

-  Added detailed YARD documentation for ``VerifiableIdentifier``,
   explaining how to securely generate and manage the required
   ``VERIFIABLE_ID_HMAC_SECRET`` key.

AI Assistance
~~~~~~~~~~~~~

-  Security analysis of external identifier derivation and hardened
   design approach was discussed and developed with AI assistance,
   including provenance tracking, validation logic, format
   normalization, and comprehensive test updates.

-  Implementation of scoped verifiable identifiers was developed with AI
   assistance to ensure cryptographic security properties and
   comprehensive test coverage.

2.0.0.pre11 - 2025-09-03
======================

.. _added-1:

Added
~~~~~

-  **Enhanced Feature System**: Introduced a hierarchical feature system
   with ancestry chain traversal for model-specific feature
   registration. This enables better organization, standardized naming,
   and automatic loading of project-specific features via the new
   ``Familia::Features::Autoloader`` module.
-  **Improved SafeDump DSL**: Replaced the internal
   ``@safe_dump_fields`` implementation with a cleaner, more robust DSL
   using ``safe_dump_field`` and ``safe_dump_fields`` methods.
-  Added ``generate_short_id`` and ``shorten_securely`` utility methods
   for creating short, secure identifiers, adapted from
   ``OT::Utils::SecureNumbers``.
-  For a detailed guide on migrating to the new feature system, see
   ``docs/migration/v2.0.0-pre11.md``.

.. _changed-1:

Changed
~~~~~~~

-  External identifier now raises an ``ExternalIdentifierError`` if the
   model does not have an objid field. Previously: returned nil. In
   practice this should never happen, since the external_identifier
   feature declares its dependency on object_identifier.
-  Moved lib/familia/encryption_request_cache.rb to
   lib/familia/encryption/request_cache.rb for consistency.
-  **Simplified ObjectIdentifier Feature Implementation**: Consolidated
   the ObjectIdentifier feature from two files (~190 lines) to a single
   file (~140 lines) by moving the ObjectIdentifierFieldType class
   inline. This reduces complexity while maintaining all existing
   functionality including lazy generation, data integrity preservation,
   and multiple generator strategies.
-  **Renamed Identifier Features to Singular Form**: Renamed
   ``object_identifier`` → ``object_identifier`` and
   ``external_identifier`` → ``external_identifier`` for more accurate
   naming. Added full-length aliases
   (``object_identifier``/``external_identifier``) alongside the short
   forms (``objid``/``extid``) for clarity when needed.
-  **Simplified ExternalIdentifier Feature Implementation**:
   Consolidated the ExternalIdentifier feature from two files (~240
   lines) to a single file (~120 lines) by moving the
   ExternalIdentifierFieldType class inline, following the same pattern
   as ObjectIdentifier.

Fixed
~~~~~

-  Fixed external identifier generation returning all zeros for
   UUID-based objids. The ``shorten_to_external_id`` method now
   correctly handles both 256-bit secure identifiers and 128-bit UUIDs
   by detecting input length and applying appropriate bit truncation
   only when needed.

.. _security-1:

Security
~~~~~~~~

-  Improved input validation in ``shorten_to_external_id`` method by
   replacing insecure character count checking with proper bit length
   calculation and explicit validation. Invalid inputs now raise clear
   error messages instead of being silently processed incorrectly.

2.0.0-pre10 - 2025-09-02
======================

.. _added-2:

Added
~~~~~

-  The ``Familia::Horreum`` initializer now supports creating an object
   directly from its identifier by passing a single argument (e.g.,
   ``Customer.new(customer_id)``). This provides a more convenient and
   intuitive way to instantiate objects from lookups.

-  Automatic indexing and class-level tracking on ``save()`` operations,
   eliminating the need for manual index updates.

-  Enhanced collection syntax supports the Ruby-idiomatic ``<<``
   operator for more natural relationship management.

.. _changed-2:

Changed
~~~~~~~

-  The ``member_of`` relationship is now bidirectional. A single call to
   ``member.add_to_owner_collection(owner)`` is sufficient to establish
   the relationship, removing the need for a second, redundant call on
   the owner object. This fixes bugs where members could be added to
   collections twice.

-  **BREAKING**: Refactored Familia Relationships API to remove “global”
   terminology and simplify method generation. (Closes #86)

-  Split ``generate_indexing_instance_methods`` into focused
   ``generate_direct_index_methods`` and
   ``generate_relationship_index_methods`` for better separation between
   direct class-level and relationship-based indexing.

-  Simplified method generation by removing complex global vs parent
   conditionals.

-  All indexes are now stored at the class level for consistency.

.. _fixed-1:

Fixed
~~~~~

-  Fixed a bug in the ``class_indexed_by`` feature where finder methods
   (e.g., ``find_by_email``) would fail to correctly instantiate objects
   from the index, returning partially-formed objects.

-  Refactored connection handling to properly cache and reuse Valkey/Redis
   connections. This eliminates repetitive “Overriding existing
   connection” warnings and improves performance.

-  Method generation now works consistently for both
   ``class_indexed_by`` and ``indexed_by`` with a ``parent:``.

-  Resolved metadata storage issues for dynamically created classes.

-  Improved error handling for nil class names in tracking
   relationships.

.. _documentation-1:

Documentation
~~~~~~~~~~~~~

-  Updated the ``examples/relationships_basic.rb`` script to reflect the
   improved, bidirectional ``member_of`` API and to ensure a clean
   database state for each run.

.. _ai-assistance-1:

AI Assistance
~~~~~~~~~~~~~

-  This refactoring was implemented with Claude Code assistance,
   including comprehensive test updates and API modernization.

2.0.0-pre9 - 2025-09-02
======================

.. _added-3:

Added
~~~~~

-  Added ``class_tracked_in`` method for global tracking relationships
   following Horreum’s established ``class_`` prefix convention
-  Added ``class_indexed_by`` method for global index relationships with
   consistent API design

.. _changed-3:

Changed
~~~~~~~

-  **BREAKING**: ``tracked_in :global, collection`` syntax now raises
   ArgumentError - use ``class_tracked_in collection`` instead
-  **BREAKING**: ``indexed_by field, index, target: :global`` syntax
   replaced with ``class_indexed_by field, index``
-  **BREAKING**: ``indexed_by field, index, target: SomeClass`` syntax
   replaced with ``indexed_by field, index, parent: SomeClass``
-  Relationships API now provides consistent parameter naming across all
   relationship types

.. _documentation-2:

Documentation
~~~~~~~~~~~~~

-  Updated Relationships Guide with new API syntax and migration
   examples
-  Updated relationships method documentation with new method signatures
-  Updated basic relationships example to demonstrate new API patterns
-  Added tryouts test coverage in
   try/features/relationships/relationships_api_changes_try.rb

2.0.0-pre8 - 2025-09-01
======================

.. _added-4:

Added
~~~~~

-  Implemented Scriv-based changelog system for sustainable
   documentation
-  Added fragment-based workflow for tracking changes
-  Created structured changelog templates and configuration

.. _documentation-3:

Documentation
~~~~~~~~~~~~~

-  Set up Scriv configuration and directory structure
-  Created README for changelog fragment workflow

.. raw:: html

   <!-- scriv-end-here -->

2.0.0-pre7 - 2025-08-31
======================

.. _added-5:

Added
~~~~~

-  Comprehensive relationships system with three relationship types:

   -  ``tracked_in`` - Multi-presence tracking with score encoding
   -  ``indexed_by`` - O(1) hash-based lookups
   -  ``member_of`` - Bidirectional membership with collision-free
      naming

-  Categorical permission system with bit-encoded permissions
-  Time-based permission scoring for temporal access control
-  Permission tier hierarchies with inheritance patterns
-  Scalable permission management for large object collections
-  Score-based sorting with custom scoring functions
-  Permission-aware queries filtering by access levels
-  Relationship validation framework ensuring data integrity

.. _changed-4:

Changed
~~~~~~~

-  Performance optimizations for large-scale relationship operations

.. _security-2:

Security
~~~~~~~~

-  GitHub Actions security hardening with matrix optimization

2.0.0-pre6 - 2025-08-15
======================

.. _added-6:

Added
~~~~~

-  New ``save_if_not_exists`` method for conditional persistence
-  Atomic persistence operations with transaction support
-  Enhanced error handling for persistence failures
-  Improved data consistency guarantees

.. _changed-5:

Changed
~~~~~~~

-  Connection provider pattern for flexible pooling strategies
-  Multi-database support with intelligent pool management
-  Thread-safe connection handling for concurrent applications
-  Configurable pool sizing and timeout management
-  Modular class structure with cleaner separation of concerns
-  Enhanced feature system with dependency management
-  Improved inheritance patterns for better code organization
-  Streamlined base class functionality

.. _fixed-2:

Fixed
~~~~~

-  Critical security fixes in Ruby workflow vulnerabilities
-  Systematic dependency resolution via multi-constraint optimization

2.0.0-pre5 - 2025-08-05
======================

.. _added-7:

Added
~~~~~

-  Field-level encryption with transparent access patterns
-  Multiple encryption providers:

   -  XChaCha20-Poly1305 (preferred, requires rbnacl)
   -  AES-256-GCM (fallback, OpenSSL-based)

-  Field-specific key derivation for cryptographic domain separation
-  Configurable key versioning supporting key rotation
-  Non-persistent field storage for sensitive runtime data
-  RedactedString wrapper preventing accidental logging/serialization
-  Memory-safe handling of sensitive data in Ruby objects
-  API-safe serialization excluding transient fields

.. _security-3:

Security
~~~~~~~~

-  Encryption field security hardening with additional validation
-  Enhanced memory protection for sensitive data handling
-  Improved key management patterns and best practices
-  Security test suite expansion with comprehensive coverage

2.0.0-pre - 2025-07-25
======================

.. _added-8:

Added
~~~~~

-  Complete API redesign for clarity and modern Ruby conventions
-  Valkey compatibility alongside traditional Valkey/Redis support
-  Ruby 3.4+ modernization with fiber and thread safety improvements
-  Connection pooling foundation with provider pattern architecture

.. _changed-6:

Changed
~~~~~~~

-  ``Familia::Base`` replaced by ``Familia::Horreum`` as the primary
   base class
-  Connection configuration moved from simple string to block-based
   setup
-  Feature activation changed from ``include`` to ``feature``
   declarations
-  Method naming updated for consistency (``delete`` → ``destroy``,
   ``exists`` → ``exists?``, ``dump`` → ``serialize``)

.. _documentation-4:

Documentation
~~~~~~~~~~~~~

-  YARD documentation workflow with automated GitHub Pages deployment
-  Comprehensive migrating guide for v1.x to v2.0.0-pre transition

.. raw:: html

   <!-- scriv-end-here -->
