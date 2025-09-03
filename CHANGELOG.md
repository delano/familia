# CHANGELOG.md

All notable changes to Familia are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--scriv-insert-here-->

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
