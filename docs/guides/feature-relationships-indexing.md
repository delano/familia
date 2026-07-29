# Relationships Indexing Guide

Indexing provides O(1) field-to-object lookups using Redis data structures, enabling fast attribute-based queries without relationship semantics.

## Core Concepts

Indexing creates fast lookups for finding objects by field values:

- **O(1) performance** - Hash/Set-based constant-time access
- **Automatic management** - Class indexes update on save/destroy
- **Flexible scoping** - Global or parent-scoped uniqueness
- **Query generation** - Automatic `find_by_*` methods

## Index Types

| Type           | Scope           | Use Case                    | Structure           |
| -------------- | --------------- | --------------------------- | ------------------- |
| `unique_index` | Class           | Global unique fields        | Redis HashKey       |
| `unique_index` | Instance        | Parent-scoped unique        | Redis HashKey       |
| `multi_index`  | Class (default) | Global non-unique groupings | Redis Set per value |
| `multi_index`  | Instance        | Parent-scoped groupings     | Redis Set per value |

## Class-Level Unique Indexing

Global unique field lookups with automatic management:

```ruby
class User < Familia::Horreum
  feature :relationships
  field :email, :username

  unique_index :email, :email_lookup
  unique_index :username, :username_lookup
end

# Automatic indexing on save
user = User.create(email: 'alice@example.com')
User.find_by_email('alice@example.com')  # => user (O(1) lookup)

# Automatic update on field change
user.update(email: 'alice.smith@example.com')
User.find_by_email('alice.smith@example.com')  # => user

# Automatic cleanup on destroy
user.destroy
User.find_by_email('alice.smith@example.com')  # => nil
```

> **Uniqueness is enforced server-side, before the transaction opens.** `save`
> claims the value with a single-key Lua compare-and-set, so two concurrent
> saves of the same value cannot both see it as free — the loser raises
> `Familia::RecordExistsError` carrying `existing_id`. The `HSET` inside save's
> MULTI only re-affirms a claim the record already holds. Every save path
> (`save`, `save_if_not_exists!`, `atomic_write`, `Familia.atomic_write`) claims
> automatically; a transaction you open yourself does not, so writing an index
> from inside one needs an explicit `claim_unique_<index>!` first — see
> `Familia::OperationModeError` under [Troubleshooting](#troubleshooting) and
> [ADR-0002](../adr/0002-watch-for-private-keys-lua-for-shared-keys.md).

### Generated Methods

| Method                         | Description       |
| ------------------------------ | ----------------- |
| `User.find_by_email(email)`    | O(1) lookup       |
| `User.index_email_for(user)`   | Manual index      |
| `User.unindex_email_for(user)` | Remove from index |
| `User.reindex_email_for(user)` | Update index      |

## Instance-Scoped Unique Indexing

Unique within parent context, allowing duplicates across parents:

```ruby
class Employee < Familia::Horreum
  feature :relationships
  field :badge_number

  unique_index :badge_number, :badge_index, within: Company
end

# Manual indexing required (needs parent context)
company1 = Company.create(name: 'Acme Corp')
company2 = Company.create(name: 'Beta Inc')

emp1 = Employee.create(badge_number: '12345')
emp1.add_to_company_badge_index(company1)

emp2 = Employee.create(badge_number: '12345')  # Same badge OK
emp2.add_to_company_badge_index(company2)

# Scoped lookups
company1.find_by_badge_number('12345')  # => emp1
company2.find_by_badge_number('12345')  # => emp2
```

> **Note**: The indexed object must be persisted before it can be added to an
> index. `add_to_*`/`update_in_*` (instance-scoped) and
> `add_to_class_*`/`update_in_class_*` (class-level) raise
> `Familia::PersistenceError` for unsaved objects, since the index entry would
> point at a record that does not exist yet. Call `save` first — for
> class-level indexes, `save` populates the index automatically anyway.

### Automatic Refresh and Cleanup

The *first* `add_to_*` is manual — `save` has no scope instance to invent one
from. After that the membership is maintained automatically: each
`add_to_*`/`update_in_*` records it in a per-object reverse index tracker — a
hash stored at `<object_key>:_idx_scopes` that maps
an entry key to the field value written into the index. The key's shape
follows the index's cardinality — unique indexes are 1:1 within a scope, so
the `"<scope_config>\t<index_name>\t<scope_id>"` triple is the whole identity;
multi indexes are 1:many, so the value is appended and each bucket the object
occupies gets its own entry:

```ruby
emp1.add_to_company_badge_index(company1)
# unique: { "company\tbadge_index\t<company1 id>" => "12345" }

emp1.add_to_company_dept_index(company1)
# multi:  { "company\tdept_index\t<company1 id>\tengineering" => "engineering" }

emp1.destroy!
company1.find_by_badge_number('12345')  # => nil
```

Both `save` and `destroy!` read the tracker before opening their transaction
(reads inside MULTI return futures, not values), then replay the writes inside
it, so index maintenance commits atomically with the object hash.

**Refresh on save.** Changing an indexed field and saving moves the tracked
entry — the old value is retracted, so it becomes reusable:

```ruby
emp1.badge_number = '99999'
emp1.save

company1.find_by_badge_number('12345')  # => nil  (retracted)
company1.find_by_badge_number('99999')  # => emp1
```

This runs inside save's transaction, where dirty tracking is still live — that
is what supplies the previous value to retract. Only scopes already registered
via `add_to_*` are refreshed. Uniqueness is validated first, outside the
transaction: if the new value is already taken in that scope, `save` raises
`Familia::RecordExistsError` and the index is left untouched, exactly as a
class-level `unique_index` behaves.

> **`atomic_write` does not refresh instance-scoped indexes.** It calls the
> shared persistence path from inside a MULTI it has already opened, and the
> tracker snapshot requires a read taken *before* the transaction (reads inside
> MULTI return futures). So scalar fields are written but instance-scoped index
> entries keep their previous values, silently. Use `save` when an indexed
> field changed, or call `update_in_*` explicitly after the `atomic_write`.

> **multi_index refresh is add-only.** A value change adds the identifier to
> the new bucket but does **not** remove it from the old one, matching
> class-level `multi_index` behavior. The object genuinely is in both buckets,
> and the tracker records both — so `destroy!` still clears every one of them.
> Call `update_in_*` explicitly when you want the old bucket retracted at the
> time of the change rather than at destroy.

**Cleanup on destroy.** The tracker stores the *indexed value*, not just the
membership, so cleanup targets the bucket the entry actually lives in — not
whatever the field happens to hold at destroy time:

```ruby
Employee.new(emp_id: emp1.identifier).destroy!  # identifier-only: no field
                                                # values in memory, cleanup
                                                # still finds the bucket
```

Two constraints follow from cleanup running write-only inside a transaction:

- The scope instance must have an identifier when `add_to_*`/`update_in_*` is
  called, or `Familia::NoIdentifier` is raised.
- The scope class must use a Symbol/String `identifier_field`, since the scope
  is rebuilt from its identifier alone during cleanup. A Proc identifier raises
  `ArgumentError` at index time.

Both are checked before the index write, so a rejected call leaves nothing
behind.

> **`delete!` does not clean up the tracker.** `delete!` removes only the main
> object hash; related keys — the `_idx_scopes` tracker included — survive, per
> its documented contract. If a *new* record is later saved under the same
> identifier, save's refresh reads the stale tracker and re-joins the tracked
> scopes on the new record's behalf (uniqueness is still validated, so a
> colliding value raises rather than evicts). Use `destroy!` for the full
> lifecycle; reach for `delete!` only when leftover related keys are
> acceptable.

### Generated Methods

**On scope class (Company):**
| Method | Description |
|--------|-------------|
| `find_by_badge_number(badge)` | Find within scope |
| `index_badge_number_for(emp)` | Add to index |
| `unindex_badge_number_for(emp)` | Remove from index |

**On indexed class (Employee):**
| Method | Description |
|--------|-------------|
| `add_to_company_badge_index(company)` | Add to company's index |
| `remove_from_company_badge_index(company)` | Remove from index |
| `in_company_badge_index?(company)` | Check if indexed |

## Class-Level Multi-Value Indexing

Class-level multi-value indexes group objects by field values at the class level. This is the default behavior when no `within:` parameter is specified.

```ruby
class Customer < Familia::Horreum
  feature :relationships
  field :role

  # Class-level multi_index (within: :class is the default)
  multi_index :role, :role_index
end

# Create customers with various roles
alice = Customer.create(custid: 'cust_001', role: 'admin')
bob = Customer.create(custid: 'cust_002', role: 'user')
charlie = Customer.create(custid: 'cust_003', role: 'admin')

# Manually add to index (or use auto-indexing via save hooks)
alice.add_to_class_role_index
bob.add_to_class_role_index
charlie.add_to_class_role_index

# Query all customers with a specific role
admins = Customer.find_all_by_role('admin')  # => [alice, charlie]
users = Customer.find_all_by_role('user')    # => [bob]

# Random sampling
sample = Customer.sample_from_role('admin', 1)  # => [random admin]
```

### Redis Key Pattern

Class-level multi-indexes use the pattern: `{classname}:{index_name}:{field_value}`

```ruby
Customer.role_index_for('admin').dbkey  # => "customer:role_index:admin"
Customer.role_index_for('user').dbkey   # => "customer:role_index:user"
```

### Generated Class Methods

| Method                                    | Description                                                  |
| ----------------------------------------- | ------------------------------------------------------------ |
| `Customer.role_index_for(value)`          | Factory returning `Familia::UnsortedSet` for the field value |
| `Customer.find_all_by_role(value)`        | Find all objects with that field value                       |
| `Customer.sample_from_role(value, count)` | Random sample of objects                                     |
| `Customer.rebuild_role_index`             | Rebuild the entire index from source data                    |

### Generated Instance Methods

| Method                                           | Description                                     |
| ------------------------------------------------ | ----------------------------------------------- |
| `customer.add_to_class_role_index`               | Add this object to its field value's index      |
| `customer.remove_from_class_role_index`          | Remove this object from its field value's index |
| `customer.update_in_class_role_index(old_value)` | Move object from old index to new index         |

### Update Operations

When a field value changes, use the update method to atomically move the object between indexes:

```ruby
old_role = customer.role
customer.role = 'superadmin'
customer.update_in_class_role_index(old_role)

# Customer is now in 'superadmin' index, removed from old 'admin' index
Customer.find_all_by_role('superadmin')  # => includes customer
Customer.find_all_by_role('admin')       # => no longer includes customer
```

## Instance-Scoped Multi-Value Indexing

For indexes scoped to a parent object, use `within:` to specify the scope class. This allows the same field values across different parent contexts.

```ruby
class Employee < Familia::Horreum
  feature :relationships
  field :department

  multi_index :department, :dept_index, within: Company
end

company = Company.create(name: 'TechCorp')

# Multiple employees in same department
[
  Employee.create(department: 'engineering'),
  Employee.create(department: 'engineering'),
  Employee.create(department: 'sales')
].each { |emp| emp.add_to_company_dept_index(company) }

# Query all in department
engineers = company.find_all_by_department('engineering')  # => [emp1, emp2]
sales_team = company.find_all_by_department('sales')       # => [emp3]

# Random sampling
sample = company.sample_from_department('engineering', 1)  # => [random engineer]
```

### Generated Methods (Instance-Scoped)

**On scope class (Company):**
| Method | Description |
|--------|-------------|
| `company.dept_index_for(value)` | Factory returning UnsortedSet for value |
| `company.find_all_by_department(dept)` | Find all in department |
| `company.sample_from_department(dept, count)` | Random sample |
| `company.rebuild_dept_index` | Rebuild index from participation |

**On indexed class (Employee):**
| Method | Description |
|--------|-------------|
| `employee.add_to_company_dept_index(company)` | Add to company's index |
| `employee.remove_from_company_dept_index(company)` | Remove from index |
| `employee.update_in_company_dept_index(company, old_dept)` | Move between indexes |

Instance-scoped multi-indexes are tracked, refreshed on `save`, and cleaned up
on `destroy!` the same way unique ones are — except that refresh is add-only.
See [Automatic Refresh and Cleanup](#automatic-refresh-and-cleanup).

## Advanced Patterns

### Composite Keys

```ruby
class ApiKey < Familia::Horreum
  field :environment, :key_type

  unique_index :environment_and_type, :env_type_index, within: Customer

  private
  def environment_and_type
    "#{environment}:#{key_type}"  # e.g., "production:read_write"
  end
end

customer.find_by_environment_and_type("production:read_only")
```

### Conditional Indexing

```ruby
class Document < Familia::Horreum
  field :status, :slug

  unique_index :slug, :slug_index, within: Project

  def add_to_project_slug_index(project)
    return unless status == 'published'  # Only index published
    super
  end
end
```

### Time Partitioning

```ruby
class Event < Familia::Horreum
  field :timestamp

  multi_index :daily_partition, :daily_events, within: User

  private
  def daily_partition
    Time.at(timestamp).strftime('%Y%m%d')  # e.g., "20241215"
  end
end

today = Familia.now.strftime('%Y%m%d')
todays_events = user.find_all_by_daily_partition(today)
```

## Key Differences

### Class vs Instance Scoping

**Class-level unique (`unique_index :email, :email_lookup`):**

- Automatic indexing on save/destroy
- System-wide uniqueness
- No parent context needed
- Examples: emails, usernames, API keys

**Class-level multi (`multi_index :role, :role_index`):**

- Default behavior (no `within:` needed)
- Groups all objects by field value at class level
- Manual indexing via instance methods
- Examples: roles, categories, statuses

**Instance-scoped (`unique_index :badge, :badge_index, within: Company`):**

- Manual indexing required
- Unique within parent only
- Requires parent context
- Examples: employee IDs, project names per team

**Instance-scoped multi (`multi_index :dept, :dept_index, within: Company`):**

- Groups objects by field value within parent scope
- Same field value allowed across different parents
- Manual indexing with parent context
- Examples: departments per company, tags per project

### Unique vs Multi Indexing

**Unique index (`unique_index`):**

- 1:1 field-to-object mapping
- Returns single object or nil
- Enforces uniqueness within scope

**Multi index (`multi_index`):**

- 1:many field-to-objects mapping
- Returns array of objects
- Allows duplicate values
- Default: class-level scope (use `within:` for instance scope)

## Rebuilding Indexes

Indexes can be automatically rebuilt from source data using auto-generated rebuild methods:

```ruby
# Class-level indexes
User.rebuild_email_lookup      # Rebuilds from all User.email values
User.rebuild_username_lookup   # Rebuilds from all User.username values

# Instance-scoped indexes
company.rebuild_badge_index    # Rebuilds from all Employee.badge_number values
```

These methods work because **indexes are derived data** - they're computed from object field values.

> **Important:** Participation data (like `@team.members`) cannot be rebuilt automatically because participations represent business decisions, not derived data. See [Why Participations Can't Be Rebuilt](../../lib/familia/features/relationships/participation/rebuild_strategies.md) for the critical distinction between indexes and participations.

**When to rebuild indexes:**

- After data migrations or bulk imports
- Recovering from index corruption
- Adding indexes to existing data

## Performance Tips

### Bulk Operations

```ruby
# Efficient bulk indexing
employees.each_slice(100) do |batch|
  company.transaction do
    batch.each { |emp| emp.add_to_company_dept_index(company) }
  end
end
```

### Index Monitoring

```ruby
# Check index sizes
company.dept_index_engineering.size  # Count in engineering
User.email_lookup.size               # Total indexed emails

# Index distribution
%w[engineering sales marketing].map { |dept|
  [dept, company.send("dept_index_#{dept}").size]
}.to_h
```

### Cleanup

```ruby
# Remove orphaned entries
company.badge_index.to_h.each do |badge, emp_id|
  unless Employee.exists?(emp_id)
    company.badge_index.delete(badge)
  end
end
```

## Index Storage Format

Index values (the object identifiers stored in hash keys and sets) are raw strings, not JSON-encoded. This is a deliberate design choice shared across all Familia collections that store object references — it ensures that lookups, membership checks, and key construction all operate on the same byte representation. See [Collection Member Serialization](field-system.md#collection-member-serialization) for the underlying serialization rules.

## Redis Key Patterns

| Type            | Pattern                             | Example                              |
| --------------- | ----------------------------------- | ------------------------------------ |
| Class unique    | `{class}:{index_name}`              | `user:email_lookup`                  |
| Class multi     | `{class}:{index_name}:{value}`      | `customer:role_index:admin`          |
| Instance unique | `{scope}:{id}:{index_name}`         | `company:123:badge_index`            |
| Instance multi  | `{scope}:{id}:{index_name}:{value}` | `company:123:dept_index:engineering` |

## Troubleshooting

### Common Issues

**Query methods not generated:**

- Check `query: true` (default) or explicitly set
- Verify `feature :relationships` declared

**Index not updating:**

- Class indexes: automatic on save/destroy
- Instance indexes: require an initial manual `add_to_*` call on a saved
  object. After that, refresh on `save` and removal on `destroy!` are both
  automatic (see
  [Automatic Refresh and Cleanup](#automatic-refresh-and-cleanup)). If a
  `multi_index` value changed, the old bucket is retained by design — use
  `update_in_*` to retract it at change time; `destroy!` clears it either way.

**`Familia::PersistenceError` from `add_to_*` / `update_in_*` (including `*_class_*` variants):**

- The object has never been saved; index writers reject unsaved objects to
  prevent dangling entries. Call `save` before indexing (class-level indexes
  populate automatically on save).

**`Familia::OperationModeError` from `add_to_class_*` / `update_in_class_*`
(`unique_index` only):**

- The write is inside a transaction *you* opened and the record holds no claim
  on the exact value being written. That in-MULTI `HSET` is only sound as a
  re-affirmation of a server-side claim; without one it is a blind write that
  can silently overwrite another record's ownership. Ordinary `save` never hits
  this — every save path claims first. Two shapes reach it:

  ```ruby
  # 1. Reassigning the indexed field inside atomic_write. The block runs
  #    INSIDE the MULTI, after the claim was taken on the OLD value.
  user.atomic_write { user.email = 'new@example.com' }   # raises

  # Fix: set the field before the block, so the claim covers the new value.
  user.email = 'new@example.com'
  user.atomic_write { user.name = 'Alice' }
  ```

  ```ruby
  # 2. Opening your own transaction after changing the field.
  old_email = user.email
  user.email = 'new@example.com'
  User.transaction { user.update_in_class_email_lookup(old_email) }  # raises

  # Fix: claim outside the MULTI, then write inside it.
  user.claim_unique_email_lookup!
  User.transaction { user.update_in_class_email_lookup(old_email) }
  ```

  The message names whichever mutator ran, so an `atomic_write` that changed a
  field reports `update_in_class_*` (the path dirty tracking routes to), not
  `add_to_class_*`. The error propagates out of the transaction block, so the
  MULTI is discarded whole: neither the index entry nor any scalar field queued
  alongside it is written, and the record reloads with its previous values.
  `update_all_indexes` routes to `update_in_class_*` and raises the same way.
  Instance-scoped (`within:`) unique indexes are *not* claim-enforced: inside a
  transaction they write blindly and log that the write is unenforced.

- Two neighbouring causes of the same error class, both pre-existing: `save`
  itself refuses to run inside a transaction, and `HashKey#claim_field` refuses
  too — a CAS verdict inside MULTI would come back as a `Future`, with nothing
  left to abort.

**`Familia::NoIdentifier` / `ArgumentError` from `add_to_*` / `update_in_*`:**

- The scope instance has no identifier, uses a Proc `identifier_field`, or its
  identifier contains a tab. In each case `destroy!` could not later rebuild
  the scope and clean the entry up safely, so the write is refused. See
  [Automatic Refresh and Cleanup](#automatic-refresh-and-cleanup).

**`Familia::RecordExistsError` from `save` (instance-scoped index):**

- Saving changed an indexed field to a value another record already holds in
  that scope. Instance-scoped uniqueness is validated on save just as
  class-level uniqueness is; the index is left untouched.

**Duplicate key errors:**

- Use `multi_index` for non-unique values
- Consider instance-scoped for contextual uniqueness

### Debugging

```ruby
# Check configuration — returns Array<IndexingRelationship> (Data objects),
# distinguished by .cardinality (:unique vs :multi)
User.indexing_relationships
# => [#<data IndexingRelationship field=:email, index_name=:email_lookup,
#            cardinality=:unique, within=nil, ...>]
User.indexing_relationships.select { |r| r.cardinality == :unique }

# Inspect index contents
User.email_lookup.to_h
# => {"alice@example.com" => "user_123", ...}

# Verify membership
employee.in_company_badge_index?(company)  # => true/false
user.indexed_in?(:email_lookup)            # => true/false (class-level indexes)
```

For the full introspection API — the `IndexingRelationship` fields, a
project-wide sweep over `Familia.members`, per-instance membership state, and
the audit/repair layer — see [Introspection](feature-relationships.md#introspection).

## See Also

- [**Relationships Overview**](feature-relationships.md) - Core concepts
- [**Methods Reference**](feature-relationships-methods.md) - Complete API
- [**Participation Guide**](feature-relationships-participation.md) - Associations
