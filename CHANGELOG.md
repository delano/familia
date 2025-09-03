# CHANGELOG.md

All notable changes to Familia are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--scriv-insert-here-->

<a id='changelog-2.0.0.pre11'></a>
## [2.0.0.pre11] - 2025-09-03 01:40:07.318100

### Added

- **Enhanced Feature System**: Introduced a hierarchical feature system with ancestry chain traversal for model-specific feature registration. This enables better organization, standardized naming, and automatic loading of project-specific features via the new `Familia::Features::Autoloader` module.
- **Improved SafeDump DSL**: Replaced the internal `@safe_dump_fields` implementation with a cleaner, more robust DSL using `safe_dump_field` and `safe_dump_fields` methods.
- Added `generate_short_id` and `shorten_securely` utility methods for creating short, secure identifiers, adapted from `OT::Utils::SecureNumbers`.
- For a detailed guide on migrating to the new feature system, see `docs/migration/v2.0.0-pre11.md`.

### Changed

- External identifier now raises an `ExternalIdentifierError` if the model does not have an objid field. Previously: returned nil. In practice this should never happen, since the external_identifier feature declares its dependency on object_identifier.
- Moved lib/familia/encryption_request_cache.rb to lib/familia/encryption/request_cache.rb for consistency.
- **Simplified ObjectIdentifiers Feature Implementation**: Consolidated the ObjectIdentifiers feature from two files (~190 lines) to a single file (~140 lines) by moving the ObjectIdentifierFieldType class inline. This reduces complexity while maintaining all existing functionality including lazy generation, data integrity preservation, and multiple generator strategies.
- **Renamed Identifier Features to Singular Form**: Renamed `object_identifiers` → `object_identifier` and `external_identifiers` → `external_identifier` for more accurate naming. Added full-length aliases (`object_identifier`/`external_identifier`) alongside the short forms (`objid`/`extid`) for clarity when needed.
- **Simplified ExternalIdentifier Feature Implementation**: Consolidated the ExternalIdentifier feature from two files (~240 lines) to a single file (~120 lines) by moving the ExternalIdentifierFieldType class inline, following the same pattern as ObjectIdentifier.

### Fixed

- Fixed external identifier generation returning all zeros for UUID-based objids. The `shorten_to_external_id` method now correctly handles both 256-bit secure identifiers and 128-bit UUIDs by detecting input length and applying appropriate bit truncation only when needed.

### Security

- Improved input validation in `shorten_to_external_id` method by replacing insecure character count checking with proper bit length calculation and explicit validation. Invalid inputs now raise clear error messages instead of being silently processed incorrectly.

<!-- scriv-end-here -->

<a id='changelog-2.0.0-pre10'></a>
## [2.0.0-pre10] - 2025-09-02 18:07:56.439890

### Added

- The `Familia::Horreum` initializer now supports creating an object directly from its identifier by passing a single argument (e.g., `Customer.new(customer_id)`). This provides a more convenient and intuitive way to instantiate objects from lookups.

- Automatic indexing and class-level tracking on `save()` operations, eliminating the need for manual index updates.
- Enhanced collection syntax supports the Ruby-idiomatic `<<` operator for more natural relationship management.

### Changed

- The `member_of` relationship is now bidirectional. A single call to `member.add_to_owner_collection(owner)` is sufficient to establish the relationship, removing the need for a second, redundant call on the owner object. This fixes bugs where members could be added to collections twice.

- **BREAKING**: Refactored Familia Relationships API to remove "global" terminology and simplify method generation. (Closes #86)
- Split `generate_indexing_instance_methods` into focused `generate_direct_index_methods` and `generate_relationship_index_methods` for better separation between direct class-level and relationship-based indexing.
- Simplified method generation by removing complex global vs parent conditionals.
- All indexes are now stored at the class level for consistency.

### Fixed

- Fixed a bug in the `class_indexed_by` feature where finder methods (e.g., `find_by_email`) would fail to correctly instantiate objects from the index, returning partially-formed objects.

- Refactored connection handling to properly cache and reuse Redis connections. This eliminates repetitive "Overriding existing connection" warnings and improves performance.

- Method generation now works consistently for both `class_indexed_by` and `indexed_by` with a `parent:`.
- Resolved metadata storage issues for dynamically created classes.
- Improved error handling for nil class names in tracking relationships.

### Documentation

- Updated the `examples/relationships_basic.rb` script to reflect the improved, bidirectional `member_of` API and to ensure a clean database state for each run.

### AI Assistance

- This refactoring was implemented with Claude Code assistance, including comprehensive test updates and API modernization.

<a id='changelog-2.0.0-pre9'></a>
# [2.0.0-pre9] - 2025-09-02 00:35:28.974817

## Added

- Added `class_tracked_in` method for global tracking relationships following Horreum's established `class_` prefix convention
- Added `class_indexed_by` method for global index relationships with consistent API design

## Changed

- **BREAKING**: `tracked_in :global, collection` syntax now raises ArgumentError - use `class_tracked_in collection` instead
- **BREAKING**: `indexed_by field, index, context: :global` syntax replaced with `class_indexed_by field, index`
- **BREAKING**: `indexed_by field, index, context: SomeClass` syntax replaced with `indexed_by field, index, parent: SomeClass`
- Relationships API now provides consistent parameter naming across all relationship types

## Documentation

- Updated Relationships Guide with new API syntax and migration examples
- Updated relationships method documentation with new method signatures
- Updated basic relationships example to demonstrate new API patterns
- Added tryouts test coverage in try/features/relationships/relationships_api_changes_try.rb


<a id='changelog-2.0.0-pre8'></a>
## [2.0.0-pre8] - 2025-09-01

#### Added

- Implemented Scriv-based changelog system for sustainable documentation
- Added fragment-based workflow for tracking changes
- Created structured changelog templates and configuration

### Documentation

- Set up Scriv configuration and directory structure
- Created README for changelog fragment workflow


<a id='changelog-2.0.0-pre7'></a>
## [2.0.0-pre7] - 2025-08-31

### Added

- Comprehensive relationships system with three relationship types:
  - `tracked_in` - Multi-presence tracking with score encoding
  - `indexed_by` - O(1) hash-based lookups
  - `member_of` - Bidirectional membership with collision-free naming
- Categorical permission system with bit-encoded permissions
- Time-based permission scoring for temporal access control
- Permission tier hierarchies with inheritance patterns
- Scalable permission management for large object collections
- Score-based sorting with custom scoring functions
- Permission-aware queries filtering by access levels
- Relationship validation framework ensuring data integrity

### Changed

- Performance optimizations for large-scale relationship operations

### Security

- GitHub Actions security hardening with matrix optimization


<a id='changelog-2.0.0-pre6'></a>
## [2.0.0-pre6] - 2025-08-15

### Added

- New `save_if_not_exists` method for conditional persistence
- Atomic persistence operations with transaction support
- Enhanced error handling for persistence failures
- Improved data consistency guarantees

### Changed

- Connection provider pattern for flexible pooling strategies
- Multi-database support with intelligent pool management
- Thread-safe connection handling for concurrent applications
- Configurable pool sizing and timeout management
- Modular class structure with cleaner separation of concerns
- Enhanced feature system with dependency management
- Improved inheritance patterns for better code organization
- Streamlined base class functionality

### Fixed

- Critical security fixes in Ruby workflow vulnerabilities
- Systematic dependency resolution via multi-constraint optimization


<a id='changelog-2.0.0-pre5'></a>
## [2.0.0-pre5] - 2025-08-05

### Added

- Field-level encryption with transparent access patterns
- Multiple encryption providers:
  - XChaCha20-Poly1305 (preferred, requires rbnacl)
  - AES-256-GCM (fallback, OpenSSL-based)
- Field-specific key derivation for cryptographic domain separation
- Configurable key versioning supporting key rotation
- Non-persistent field storage for sensitive runtime data
- RedactedString wrapper preventing accidental logging/serialization
- Memory-safe handling of sensitive data in Ruby objects
- API-safe serialization excluding transient fields

### Security

- Encryption field security hardening with additional validation
- Enhanced memory protection for sensitive data handling
- Improved key management patterns and best practices
- Security test suite expansion with comprehensive coverage


<a id='changelog-2.0.0-pre'></a>
## [2.0.0-pre] - 2025-07-25

### Added

- Complete API redesign for clarity and modern Ruby conventions
- Valkey compatibility alongside traditional Redis support
- Ruby 3.4+ modernization with fiber and thread safety improvements
- Connection pooling foundation with provider pattern architecture

### Changed

- `Familia::Base` replaced by `Familia::Horreum` as the primary base class
- Connection configuration moved from simple string to block-based setup
- Feature activation changed from `include` to `feature` declarations
- Method naming updated for consistency (`delete` → `destroy`, `exists` → `exists?`, `dump` → `serialize`)

### Documentation

- YARD documentation workflow with automated GitHub Pages deployment
- Comprehensive migration guide for v1.x to v2.0.0-pre transition

<!-- scriv-end-here -->
