# lib/familia/features/relationships/README.md
---

## Core Modules

**relationships.rb** - Main orchestrator that unifies all relationship functionality into a single feature, providing the public API and coordinating between all submodules.

**indexing.rb** - O(1) lookup capability via Valkey/Redis hashes/sorted sets. Enables fast field-based searches both globally (`context: :global`) and parent-scoped (`context: ParentClass`).

**tracking.rb** - Multi-presence management where objects can exist in multiple collections simultaneously with score-encoded metadata (timestamps, permissions, etc.).

**membership.rb** - Collision-free method generation for relationship operations. Ensures objects can belong to multiple collections without method name conflicts.

**querying.rb** - Advanced search operations across collections with filtering, unions, intersections, and permission-based access control.

**cascading.rb** - Automated cleanup and dependency management. Handles what happens when objects are deleted (remove from collections, update indexes, etc.).

## Supporting Modules

**score_encoding.rb** - Embeds metadata directly into Valkey/Redis scores for efficient storage and retrieval without additional round trips.

**database_operations.rb** - Low-level Valkey/Redis command abstractions and atomic multi-collection operations via pipelines/transactions.

**permission_management.rb** - Score-based permission encoding allowing fine-grained access control within collections.

## Key Philosophy

The entire system embraces "where does this appear?" rather than "who owns this?" - enabling objects to exist in multiple contexts simultaneously while maintaining fast lookups and atomic operations.
