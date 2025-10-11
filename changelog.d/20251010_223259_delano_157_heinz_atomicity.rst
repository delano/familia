Database Operations and Error Handling Improvements
==================================================

Added
-----

- New error hierarchy with ``PersistenceError``, ``HorreumError``, ``CreationError``, and ``OptimisticLockError`` classes for better error categorization and handling
- ``watch``, ``unwatch``, and ``discard`` Redis commands for optimistic locking support
- Enhanced database command logging with structured format for pipelined and transaction operations
- ``save_fields`` method in Persistence module for selective field updates
- Comprehensive documentation for Horreum database commands with parameter descriptions and return value specifications

Changed
-------

- **BREAKING**: Renamed ``Management.create`` to ``create!`` to follow Rails conventions and indicate potential exceptions
- **BREAKING**: Updated ``save_if_not_exists`` to ``save_if_not_exists!`` with optimistic locking and automatic retry logic (up to 3 attempts)
- Improved ``save`` method to use single atomic transaction encompassing field updates, expiration setting, index updates, and instance collection management
- Enhanced ``delete!`` methods to work correctly within Redis transactions
- Updated timestamp fields (``created``, ``updated``) to use float values instead of integers for higher precision
- Refined log message formatting for better readability and debugging
- Removed deprecated Connection instance methods for Horreum models in favor of class-level database operations
- Clarified "pipelined" terminology throughout codebase (renamed from "pipeline" for consistency with Redis documentation)

Fixed
-----

- Resolved atomicity issues in save operations by consolidating all related operations into single Redis transaction
- Fixed race conditions in ``save_if_not_exists`` using proper watch/multi/exec pattern with optimistic locking
- Corrected transaction handling to ensure proper cleanup and error propagation

Documentation
-------------

- Added comprehensive parameter documentation for database command methods including return value specifications
- Enhanced inline documentation for Redis operation methods with usage examples and behavior descriptions

AI Assistance
-------------

- Code review and optimization suggestions for transaction atomicity improvements
- Assistance with error hierarchy design and implementation patterns
- Documentation enhancement and formatting improvements
