CHANGELOG.rst
=============

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

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

- **SortedSet#add**: Full ZADD option support (NX, XX, GT, LT, CH) for atomic conditional operations and accurate change tracking. This enables proper index management with timestamp preservation, update-only operations, conditional score updates, and analytics tracking. Closes issue #135.

Fixed
-----

- Restored objid provenance tracking when loading objects from Redis. The ``ObjectIdentifier`` feature now infers the generator type (:uuid_v7, :uuid_v4, :hex) from the objid format, enabling dependent features like ``ExternalIdentifier`` to derive external identifiers from loaded objects. PR #131

AI Assistance
-------------

- Claude Code assisted with implementing the ``infer_objid_generator`` method and updating the setter logic in ``lib/familia/features/object_identifier.rb``.

- Claude Code assisted with Redis ZADD option semantics research, mutual exclusivity validation design, comprehensive test case matrix creation (50+ test cases), and YAML documentation examples.

.. _changelog-2.0.0.pre16:

2.0.0.pre16 — 2025-09-30
========================

Added
-----

- Added support for instance-scoped unique indexes via ``unique_index`` with ``within:`` parameter. Issue #128

  Example: ``unique_index :badge_number, :badge_index, within: Company`` creates per-company unique badge lookups using HashKey DataType.

Changed
-------

- **BREAKING**: Consolidated relationships API by replacing ``tracked_in`` and ``member_of`` with unified ``participates_in`` method. PR #110
- **BREAKING**: Renamed ``context_class`` terminology to ``target_class`` throughout relationships module for clarity
- **BREAKING**: Removed ``tracking.rb`` and ``membership.rb`` modules, merged functionality into ``participation.rb``
- **BREAKING**: Updated method names and configuration keys to use ``target`` instead of ``context`` terminology
- Added ``bidirectional`` parameter to ``participates_in`` to control generation of convenience methods (default: true)
- Added support for different collection types (sorted_set, set, list) in unified ``participates_in`` API
- Renamed ``class_tracked_in`` to ``class_participates_in`` for consistency

- Renamed DataType classes to avoid Ruby namespace confusion: ``Familia::String`` → ``Familia::StringKey``, ``Familia::List`` → ``Familia::ListKey``
- Added dual registration for both traditional and explicit method names (``string``/``stringkey``, ``list``/``listkey``)
- Updated ``Counter`` and ``Lock`` to inherit from ``StringKey`` instead of ``String``

- **BREAKING:** Renamed indexing API methods for clarity. Issue #128

  - ``class_indexed_by`` → ``unique_index`` (1:1 field-to-object mapping via HashKey)
  - ``indexed_by`` → ``multi_index`` (1:many field-to-objects mapping via UnsortedSet)
  - Parameter ``target:`` → ``within:`` for consistency across both index types

- **BREAKING:** Changed ``multi_index`` to use ``UnsortedSet`` instead of ``SortedSet``. Issue #128

  Multi-value indexes no longer include temporal scoring. This aligns with the design philosophy that indexing is for finding objects by attribute, not ordering them. Sort results in Ruby when needed: ``employees.sort_by(&:hire_date)``

Documentation
-------------

- Updated overview documentation to explain dual naming system and namespace safety benefits
- Enhanced examples to demonstrate both traditional and explicit DataType method naming

- Updated inline module documentation
    - ``Familia::Features::Relationships::Indexing`` with comprehensive examples, terminology guide, and design philosophy.
    - ``Familia::Features::Relationships::Participation`` to clarify differences from indexing module.

AI Assistance
-------------

- Comprehensive analysis of existing ``tracked_in`` and ``member_of`` implementations
- Design and implementation of unified ``participates_in`` API integrating both functionalities
- Systematic refactoring of codebase terminology from context to target
- Complete test suite updates to verify API consolidation and new functionality

- DataType class renaming and dual registration system implementation designed and developed with Claude Code assistance
- All test updates and documentation enhancements created with AI support

- Architecture design, implementation, test updates, and documentation for indexing API refactoring completed with Claude Code assistance. Issue #128

.. _changelog-2.0.0.pre14:

2.0.0.pre14 — 2025-09-08
========================

Changed
-------

- **BREAKING CHANGE**: Renamed ``Familia::Refinements::TimeUtils`` to ``Familia::Refinements::TimeLiterals`` to better reflect the module's primary purpose of enabling numeric and string values to be treated as time unit literals (e.g., ``5.minutes``, ``"30m".in_seconds``). Functionality remains the same - only the module name has changed. Users must update their refinement usage from ``using Familia::Refinements::TimeUtils`` to ``using Familia::Refinements::TimeLiterals``.

Fixed
-----

- Fixed ExternalIdentifier HashKey method calls by replacing incorrect ``.del()`` calls with ``.remove_field()`` in three critical locations: extid setter (cleanup old mapping when changing value), find_by_extid (cleanup orphaned mapping when object not found), and destroy! (cleanup mapping when object is destroyed). Added comprehensive test coverage for all scenarios to prevent regression. PR #100

AI Assistance
-------------

- Claude Code helped rename TimeUtils to TimeLiterals throughout the codebase, including module name, file path, all usage references, and updating existing documentation.
- Gemini 2.5 Flash wrote the inline docs for TimeLiterals based on a discussion re: naming rationale.
- Claude Code fixed the ExternalIdentifier HashKey method bug, replacing incorrect ``.del()`` calls with proper ``.remove_field()`` calls, and implemented test coverage for the affected scenarios.

.. _changelog-2.0.0.pre13:

2.0.0.pre13 — 2025-09-07
========================

Added
-----

- **Feature Autoloading System**: Features can now automatically discover and load extension files from your project directories. When you include a feature like ``safe_dump``, Familia searches for configuration files using conventional patterns like ``{model_name}/{feature_name}_*.rb``, enabling clean separation between core model definitions and feature-specific configurations. See ``docs/migrating/v2.0.0-pre13.md`` for migration details.

- **Consolidated autoloader architecture**: Introduced ``Familia::Features::Autoloader`` as a shared utility for consistent file loading patterns across the framework, supporting both general-purpose and feature-specific autoloading scenarios.

- Added ``PER_MONTH`` constant (2,629,746 seconds = 30.437 days) derived from Gregorian year for consistent month calculations.
- Added ``months``, ``month``, and ``in_months`` conversion methods to Numeric refinement.
- Added month unit mappings (``'mo'``, ``'month'``, ``'months'``) to TimeLiterals ``UNIT_METHODS`` hash.

- **Error Handling**: Added ``NotSupportedError`` for invalid serialization mode combinations in encryption subsystem. PR #97

Changed
-------

- Refactored time and numeric extensions from global monkey patches to proper Ruby refinements for better encapsulation and reduced global namespace pollution
- Updated all internal classes to use refinements via ``using Familia::Refinements::TimeLiterals`` statements
- Added centralized ``RefinedContext`` module in test helpers to support refinement testing in tryouts files

- Updated ``PER_YEAR`` constant to use Gregorian year (31,556,952 seconds = 365.2425 days) for calendar consistency.

- **Performance**: Replaced stdlib JSON with OJ gem for 2-5x faster JSON operations and reduced memory allocation. All existing code remains compatible through mimic_JSON mode. PR #97

- **Encryption**: Enhanced serialization safety for encrypted fields with improved ConcealedString handling across different JSON processing modes. Strengthened protection against accidental data exposure during serialization. PR #97

Fixed
-----

- Fixed byte conversion logic in ``to_bytes`` method to correctly handle exact 1024-byte boundaries (``size >= 1024`` instead of ``size > 1024``)
- Resolved refinement testing issues in tryouts by implementing ``eval``-based code execution within refined contexts

- Fixed TimeLiterals refinement ``months_old`` and ``years_old`` methods returning incorrect values (raw seconds instead of months/years). The underlying ``age_in`` method now properly handles ``:months`` and ``:years`` units. Issue #94.
- Fixed calendar consistency issue where ``12.months != 1.year`` by updating ``PER_YEAR`` to use Gregorian year (365.2425 days) and defining ``PER_MONTH`` as ``PER_YEAR / 12``.

Security
--------

- **Encryption**: Improved concealed value protection during JSON serialization, ensuring encrypted data remains properly protected across all OJ serialization modes. PR #97

Documentation
-------------

- **Feature System Autoloading Guide**: Added comprehensive guide at ``docs/guides/Feature-System-Autoloading.md`` explaining the new autoloading system, including file naming conventions, directory patterns, and usage examples.
- **Enhanced API documentation**: Added detailed YARD documentation for autoloading modules and methods.

AI Assistance
-------------

- Provided comprehensive analysis of Ruby refinement scoping issues and designed the eval-based testing solution
- Assisted with refactoring global extensions to proper refinements while maintaining backward compatibility
- Helped debug and fix the byte conversion boundary condition bug

- Significant AI assistance in architectural design and implementation of the feature-specific autoloading system, including pattern matching logic, Ruby introspection methods, and comprehensive debugging of edge cases and thread safety considerations.

- Claude Code assisted with implementing the fix for broken ``months_old`` and ``years_old`` methods in the TimeLiterals refinement, including analysis, implementation, testing, and documentation.

- Performance optimization research and OJ gem integration strategy, including compatibility analysis and testing approach for seamless stdlib JSON replacement. PR #97

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
