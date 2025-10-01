<!--lib/familia/features/relationships/README.md-->

## Core Modules

**relationships.rb** - Main orchestrator that unifies all relationship functionality into a single feature, providing the public API and coordinating between all submodules.

**indexing.rb** - O(1) lookup capability via Valkey/Redis hashes and sets. Enables fast field-based searches when parent-scoped (within: ParentClass). Creates instance methods on parent class for scoped lookups.

**participation.rb** - Multi-presence management where objects can exist in multiple collections simultaneously with score-encoded metadata (timestamps, permissions, etc.). All add/remove operations use transactions for atomicity.

## Quick API Guide

**participates_in** - Collection membership ("this object belongs in that collection")
```ruby
participates_in Organization, :members, score: :joined_at, bidirectional: true
# Creates: org.members, org.add_member(), customer.add_to_organization_members()
```

**unique_index** - Fast unique lookups ("find object by unique field value")
```ruby
unique_index :email, :email_index, within: Organization  # Scoped: org.find_by_email()
```

**multi_index** - Fast multi-value lookups ("find all objects by field value")
```ruby
multi_index :department, :dept_index, within: Organization
# Creates: org.sample_from_department(), org.find_all_by_department()
```

## Key Philosophy

The entire system embraces "where does this appear?" rather than "who owns this?" - enabling objects to exist in multiple contexts simultaneously while maintaining fast lookups and atomic operations.

## When to Use Which

<details>
<summary>📋 participates_in vs indexing - Decision Guide</summary>

### participates_in - Collection Membership
- **Purpose**: "This object belongs in that collection"
- **Storage**: SortedSet/Set/List of object IDs with optional scores
- **Use for**: Membership relationships, ordered lists, scored collections
- **Example**: Customers in an Organization, Tasks in a Project
- **Atomicity**: Transactions for all operations (collection + reverse index)

```ruby
participates_in Organization, :members, score: :joined_at
# Creates: org.members (SortedSet), org.add_member(), customer.add_to_organization_members()
```

### unique_index - Fast Unique Lookups
- **Purpose**: "Find THE object by unique field value"
- **Storage**: HashKey for O(1) field-to-object mapping
- **Use for**: Email lookups, username searches, unique IDs
- **Example**: Find customer by email, find employee by badge number
- **Atomicity**: Transactions for updates (remove old + add new)

```ruby
unique_index :email, :email_index, within: Organization
# Creates: org.find_by_email(), org.find_all_by_email()
```

### multi_index - Fast Multi-Value Lookups
- **Purpose**: "Find ALL objects by shared field value"
- **Storage**: UnsortedSet for O(1) field-to-objects mapping
- **Use for**: Grouping by department, status, category, tags
- **Example**: All employees in a department, all tasks with status
- **Atomicity**: Transactions for updates (remove from old set + add to new set)

```ruby
multi_index :department, :dept_index, within: Organization
# Creates: org.sample_from_department(dept, count), org.find_all_by_department(dept)
```

</details>

> [!NOTE]
> **Scoping Patterns**: `unique_index` and `multi_index` use the `within:` parameter for instance-scoping, while participation uses distinct method names (`participates_in` vs `class_participates_in`) to reflect fundamentally different semantics (instance collections vs auto-tracking all instances).

> [!TIP]
> **Quick Decision Guide**
> - Need to store a collection of objects? → `participates_in`
> - Need to find ONE object by unique field? → `unique_index`
> - Need to find MANY objects by shared field? → `multi_index`
> - Combination? → Use all three together (very common)

```ruby
class Customer < Familia::Horreum
  feature :relationships

  participates_in Organization, :members    # Customer belongs to org
  unique_index :email, :email_index, within: Organization  # Find by unique email
end
```

> [!NOTE]
> **Key**: `participates_in` = collections, `unique_index` = unique lookups, `multi_index` = group lookups.
