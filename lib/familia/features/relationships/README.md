# lib/familia/features/relationships/README.md

## Core Modules

**relationships.rb** - Main orchestrator that unifies all relationship functionality into a single feature, providing the public API and coordinating between all submodules.

**indexing.rb** - O(1) lookup capability via Valkey/Redis sorted sets. Enables fast field-based searches when parent-scoped (target: ParentClass). Creates instance methods on context class for scoped lookups.

**participation.rb** - Multi-presence management where objects can exist in multiple collections simultaneously with score-encoded metadata (timestamps, permissions, etc.). Includes integrated convenience methods via member_methods parameter.

**querying.rb** - Advanced search operations across collections with filtering, unions, intersections, and permission-based access control.

**cascading.rb** - Automated cleanup and dependency management. Handles what happens when objects are deleted (remove from collections, update indexes, etc.).

## Quick API Guide

**participates_in** - Collection membership ("this object belongs in that collection")
```ruby
participates_in Organization, :members, score: :joined_at, member_methods: true
# Creates: org.members, org.add_member(), customer.add_to_organization_members()
```

**indexed_by** - Fast lookups ("find objects by field value")
```ruby
indexed_by :email, :email_index, context: Organization  # Scoped: org.find_by_email()
```

## Supporting Modules

**score_encoding.rb** - Embeds metadata directly into Valkey/Redis scores for efficient storage and retrieval without additional round trips.

**database_operations.rb** - Low-level Valkey/Redis command abstractions and atomic multi-collection operations via pipelines/transactions.

**permission_management.rb** - Score-based permission encoding allowing fine-grained access control within collections.

## Key Philosophy

The entire system embraces "where does this appear?" rather than "who owns this?" - enabling objects to exist in multiple contexts simultaneously while maintaining fast lookups and atomic operations.

⏺ participates_in vs indexed_by - When to Use Which

participates_in - Collection Membership
- Purpose: "This object belongs in that collection"
- Storage: SortedSet of object IDs with scores
- Use for: Membership relationships, ordered lists, scored collections
- Example: Customers in an Organization, Tasks in a Project

participates_in Organization, :members, score: :joined_at
# Creates: org.members (SortedSet), org.add_member(), customer.add_to_organization_members()

indexed_by - Fast Lookups
- Purpose: "Find objects by field value quickly"
- Storage: Hash or SortedSet for O(1) field-based lookups
- Use for: Search indexes, unique constraints, field-based queries
- Example: Find customer by email, find domain by name

indexed_by :email, :email_index, context: Organization
# Creates: org.find_by_email(), org.find_all_by_email()

Quick Decision Guide

- Need to store a collection of objects? → participates_in
- Need to find objects by a field value? → indexed_by
- Both? → Use both (very common pattern)

class Customer < Familia::Horreum
  participates_in Organization, :members    # Customer belongs to org
  indexed_by :email, :email_index, context: Organization  # Find by email within org
end

Key: participates_in = collections of records, indexed_by = search.
