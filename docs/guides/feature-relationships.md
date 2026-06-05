# Relationships Feature Guide

The Relationships feature provides automatic bidirectional associations between Familia objects, eliminating manual foreign key management while enabling efficient queries through Redis-native data structures.

> [!TIP]
> Enable with `feature :relationships` and define associations using `participates_in` for automatic method generation.

## Quick Start

```ruby
class Customer < Familia::Horreum
  feature :relationships
  # Collection 'domains' created automatically
end

class Domain < Familia::Horreum
  feature :relationships
  participates_in Customer, :domains
end

# Automatic bidirectional relationship management
customer.add_domains_instance(domain)      # Add relationship
domain.in_customer_domains?(customer)      # => true
domain.customer_instances                  # => [customer]
```

## Core Capabilities

### Participation - Bidirectional Associations

Create semantic relationships between objects with automatic reverse tracking:

```ruby
class User < Familia::Horreum
  feature :relationships
  participates_in Team, :members, score: :joined_at
  participates_in Team, :admins
end

# Generated methods on Team (target)
team.add_members_instance(user)           # Add single member
team.add_members([user1, user2])          # Bulk add
team.members.range(0, 9)                  # First 10 members

# Generated methods on User (participant)
user.add_to_team_members(team)            # Add self to team
user.in_team_admins?(team)                # Check membership
user.team_instances                       # All teams (members + admins)
```

### Indexing - Fast Attribute Lookups

Enable O(1) field-based queries with automatic index management:

```ruby
class User < Familia::Horreum
  feature :relationships
  field :email, :username

  # Global unique indexes (auto-managed on save/destroy)
  unique_index :email, :email_lookup
  unique_index :username, :username_lookup
end

User.find_by_email("alice@example.com")   # O(1) lookup
User.find_by_username("alice")            # O(1) lookup

# Scoped indexing (manual management required)
class Employee < Familia::Horreum
  feature :relationships
  unique_index :badge_number, :badge_index, within: Company
  multi_index :department, :dept_index, within: Company
end

employee.add_to_company_badge_index(company)
company.find_by_badge_number("12345")     # Scoped lookup
company.find_all_by_department("engineering")  # Multi-value
```

### Scoring - Semantic Ordering

Use scores for temporal tracking, priority systems, or custom ordering:

```ruby
class Task < Familia::Horreum
  feature :relationships
  field :priority, :created_at

  # Field-based scoring
  participates_in Project, :tasks, score: :priority

  # Lambda-based scoring
  participates_in Sprint, :tasks, score: -> {
    priority * 100 + (Familia.now - created_at) / 3600
  }
end

project.tasks.range(0, 4, order: 'DESC')  # Top 5 by priority
sprint.tasks.range_by_score(500, '+inf')  # High priority tasks
```

## Generated Method Reference

### When Domain declares `participates_in Customer, :domains`

| Class | Method | Purpose |
|-------|--------|---------|
| **Customer** | `domains` | Access collection |
| | `add_domains_instance(domain)` | Add single item |
| | `add_domains([domains])` | Bulk add |
| | `remove_domains_instance(domain)` | Remove item |
| **Domain** | `add_to_customer_domains(customer)` | Add to collection |
| | `remove_from_customer_domains(customer)` | Remove from collection |
| | `in_customer_domains?(customer)` | Check membership |
| | `score_in_customer_domains(customer)` | Get score (sorted_set) |
| | `customer_instances` | Load all customers |
| | `customer_ids` | Get customer IDs |
| | `customer?` | Has any customers? |
| | `customer_count` | Count relationships |

## Common Patterns

### Multiple Collections

```ruby
class User < Familia::Horreum
  feature :relationships
  participates_in Project, :contributors
  participates_in Project, :reviewers
  participates_in Organization, :employees, as: :employers
end

# Separate methods per collection
user.add_to_project_contributors(project)
user.add_to_project_reviewers(project)

# Custom reverse method names
user.employers_instances  # Instead of organization_instances
```

### Class-Level Tracking

```ruby
class Customer < Familia::Horreum
  feature :relationships
  class_participates_in :all_customers, score: :created_at
  class_participates_in :premium_customers,
    score: ->(c) { c.tier == 'premium' ? c.last_activity : 0 }
end

Customer.all_customers.size               # Total count
Customer.premium_customers.range(0, 9)    # Top 10 premium
```

### Performance Optimization

```ruby
# Bulk operations
team.add_members([user1, user2, user3])

# Pagination
team.members.range(0, 19)                 # First 20
team.members.range(20, 39)                # Next 20

# Direct ID access (no object loading)
team.members.to_a                         # Just IDs
team.member_instances                     # Load objects
```

## Introspection

The relationships feature exposes its configuration and state at three levels:
per-class metadata (what a class *declares*), a project-wide sweep (composed
from the global class registry), and per-instance state (which indexes and
collections a specific object *currently belongs to*).

### Per-Class: `indexing_relationships` and `participation_relationships`

Every class with `feature :relationships` gains two class-level readers.

`indexing_relationships` returns an `Array<IndexingRelationship>` covering both
`unique_index` and `multi_index` declarations — they are distinguished by the
`cardinality` field, not by separate accessors:

```ruby
User.indexing_relationships
# => [#<data IndexingRelationship field=:email, index_name=:email_lookup,
#            cardinality=:unique, within=nil, ...>, ...]
```

Each `IndexingRelationship` is a `Data.define` exposing:

| Member | Type | Description |
|--------|------|-------------|
| `.field` | Symbol | The indexed field, e.g. `:email` |
| `.index_name` | Symbol | The index name, e.g. `:email_lookup` |
| `.cardinality` | Symbol | `:unique` (1:1) or `:multi` (1:many) — **this is how you tell index types apart** |
| `.within` | Class, Symbol, or nil | `nil` (class-level unique), `:class` (class-level multi), or the scope Class (instance-scoped) |
| `.scope_class` | Class/Symbol | Scope class for `within:` indexes |
| `.query` | Boolean | Whether `find_by_*` methods were generated |
| `.class_level?` | Boolean | Convenience: `within.nil? || within == :class` |
| `.scope_class_config_name` | String | Normalized config name of the scope class |

```ruby
# Just the unique indexes:
User.indexing_relationships.select { |r| r.cardinality == :unique }

# Just the instance-scoped indexes:
User.indexing_relationships.reject(&:class_level?)
```

The participation parallel is `participation_relationships`, which returns an
`Array<ParticipationRelationship>` describing every `participates_in` /
`class_participates_in` declaration (target class, collection name, scoring
strategy, collection type, and more):

```ruby
Domain.participation_relationships
# => [#<data ParticipationRelationship target_class=Customer,
#            collection_name=:domains, type=:sorted_set, ...>]
```

### Project-Wide: `Familia.index_descriptors` and friends

To enumerate every index across the whole application, use the project-wide
aggregators. They sweep `Familia.members` (the global registry of every
`Familia::Horreum` subclass) and return `Familia::IndexDescriptor` objects that
pair each index with its owning class:

```ruby
Familia.index_descriptors               # => Array<IndexDescriptor> (every index)
Familia.unique_indexes                   # cardinality: :unique
Familia.multi_indexes                    # cardinality: :multi
Familia.participation_descriptors        # => Array<[owner_class, ParticipationRelationship]>

# All filter by cardinality (via the helper), class_level:, and owner:
Familia.unique_indexes(class_level: true)        # exclude instance-scoped
Familia.unique_indexes(owner: User)              # one class only
```

An `IndexDescriptor` exposes the underlying relationship's metadata (`field`,
`index_name`, `cardinality`, `within`, `class_level?`, `unique?`, `query?`) plus
a stable `coordinate` (`"User:email_lookup"`) — and, crucially, **behavior that
hides the index's storage layout**: `each_record` and `rebuild!` work without the
caller knowing the method-naming conventions.

```ruby
# Iterate the records behind every class-level unique index — no internals:
Familia.unique_indexes(class_level: true).each do |idx|
  idx.each_record { |record| record.touch }
end
```

> [!NOTE]
> `Familia.members` includes **all** loaded `Horreum` subclasses (the framework's
> own models, your models, and any test classes), and a class only appears
> **after it has been required**. Run project-wide sweeps once your application is
> fully loaded; scope with `owner:` when you want a single class.

### Detecting stale index data (boot guard)

The v2.10.0 [unique-index storage change](../migrating/v2.10.0.md#unique-index-storage-format)
is read-compatible, but indexes written under 2.9.x hold legacy JSON-encoded
identifiers until rebuilt — and an un-rebuilt index can make a `find_by_*` lookup
silently miss. The introspection layer can **detect and fix this before it bites**:

```ruby
# Which class-level unique indexes still hold pre-2.10.0 data?
Familia.stale_indexes                     # => Array<IndexDescriptor>

# Boot guard / CI smoke test — fail fast (or warn) on stale data:
Familia.assert_indexes_current!                       # raises Familia::Problem if stale
Familia.assert_indexes_current!(on_stale: :warn)      # warns and returns false

# The v2.10.0 migration sweep — rebuild everything stale, no internals required:
Familia.stale_indexes.each(&:rebuild!)
```

`stale_indexes` samples each index's raw values (via `HRANDFIELD`/`HMGET`, so no
deserialize and no warning spam) and reuses the same `Familia.legacy_json_encoded?`
predicate as the read path, so detection and stripping never disagree.

### Per-Instance: membership state

Where the class-level readers describe *configuration*, the instance methods
describe *current state* — which indexes and collections a specific object
actually belongs to.

| Method | Returns | Description |
|--------|---------|-------------|
| `current_indexings` | `Array<Hash>` | Indexes this object currently appears in. Class-level entries are verified against the database; instance-scoped entries are marked `index_key: 'scope_dependent'` (they need a scope instance to verify). |
| `indexed_in?(:index_name)` | Boolean | Whether the object is present in the named class-level index. Instance-scoped indexes return `false` (a scope instance is required). |
| `current_participations` | `Array<Hash>` | Participation collections this object is a member of, with score/position where applicable. |
| `relationship_status` | Hash | Aggregate snapshot: `{ identifier:, current_participations:, index_memberships: }`. |

```ruby
user.indexed_in?(:email_lookup)   # => true
user.current_indexings
# => [{ scope_class: 'class', index_name: :email_lookup, field: :email,
#       cardinality: :unique, type: 'unique_index', ... }]

user.relationship_status
# => { identifier: "user_123",
#      current_participations: [...],
#      index_memberships: [...] }
```

### Verifying and repairing indexes

If your goal is to *verify or repair* indexes rather than simply *list* them,
reach for the audit/repair layer instead of rolling your own consistency
checks. It is built on the same `indexing_relationships` /
`participation_relationships` metadata and is mixed into every Horreum subclass
as class methods (`AuditMethods` / `RepairMethods` in
`lib/familia/horreum/management/`):

```ruby
User.health_check          # Aggregate consistency report
User.audit_unique_indexes  # Detect drift in unique indexes
User.repair_indexes!       # Reconcile indexes against current instances
```

## Serialization of Collection Members

Participation collections store object identifiers as **raw strings**: when you
add a Familia object, `serialize_value` extracts its `.identifier` and stores it
without JSON encoding, so identifiers match cleanly and build correct Redis keys
(no `"\"abc-123\""` quoting artifacts).

Whether a *raw string identifier* (rather than an object) round-trips the same
way depends on how the collection is declared:

- **Reference collections** (`class:` + `reference: true`) — such as `unique_index`
  hash keys and Horreum's built-in `instances` set — normalize both paths, so an
  object and its raw string identifier resolve identically.
- **`participates_in` collections** use the loading-only `record_class:` option,
  which does not change serialization. Pass Familia **objects** (not raw string
  identifiers) to `add` / `member?` / `remove` so the identifier is extracted
  consistently.

See [Collection Member Serialization](field-system.md#collection-member-serialization)
for the authoritative serialization rules.

## Best Practices

1. **Use bulk methods** for multiple additions: `add_domains([d1, d2, d3])`
2. **Paginate large collections**: `range(0, 19)` instead of loading all
3. **Leverage reverse methods**: `domain.customer_instances` for efficient loading
4. **Clean up on destroy**: Call `cleanup_relationships` before deletion
5. **Validate before adding**: Check capacity/eligibility in overridden methods

## See Also

- [**Relationship Methods**](feature-relationships-methods.md) - Complete API reference
- [**Participation Guide**](feature-relationships-participation.md) - Deep dive into associations
- [**Indexing Guide**](feature-relationships-indexing.md) - Attribute lookup patterns
