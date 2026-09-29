# Transaction Safety in Familia

## Overview

Familia uses Redis transactions (MULTI/EXEC) for atomic operations. However, Redis transactions have a fundamental limitation: commands within a transaction return `Redis::Future` objects instead of actual values. These Future objects cannot be inspected until the transaction completes.

## Core Rules

### 1. No Save Operations Inside Transactions or Pipelines

**Rule**: The following methods cannot be called within a transaction or pipeline context:
- `save`
- `save!`
- `save_if_not_exists!`
- `create!` (calls `save_if_not_exists!` internally)
- `build`
- `atomic_write` and `Familia.atomic_write` (they open their own MULTI/EXEC)

**Rationale**: These methods need to read current state for validation (checking existence, validating unique constraints), which would return uninspectable Redis::Future objects inside transactions and pipelines.

**Error**: Calling these methods inside a transaction or pipeline raises `Familia::OperationModeError`

**Correct Pattern**:
```ruby
# ✅ GOOD: Save before transaction
customer = Customer.new(email: 'test@example.com')
customer.save  # Validates unique constraints here

customer.transaction do
  # Perform other atomic operations
  customer.increment(:login_count)
  customer.hset(:last_login, Familia.now.to_i)
end

# ❌ BAD: Save inside transaction
Customer.transaction do
  customer = Customer.new(email: 'test@example.com')
  customer.save  # Raises Familia::OperationModeError
end
```

### 2. Unique Index Guards Run Before Transactions

**Rule**: Unique constraint validation (`guard_unique_indexes!`) and the server-side claim (`claim_unique_<index>!`) must execute outside transaction context.

**Rationale**: Guards need to read current index state to check for duplicates, and the claim's CAS verdict must be inspectable. Inside a transaction, both return Redis::Future objects that cannot be inspected.

**Implementation**: `save` — and the partial writers `commit_fields`, `save_fields`, and `multi_field_update` — automatically guard and claim BEFORE starting their internal transaction, then re-affirm the claim inside it.

**Scope note**: `save_fields` and `multi_field_update` guard and claim only the indexes covering the fields being written. `commit_fields` writes the full hash, so it guards and claims EVERY class-level unique index — one CAS round-trip per index — even when the indexed value is unchanged (an unchanged value resolves as `:owned` and succeeds). If you are updating a small set of non-indexed fields on a class with several unique indexes, `save_fields`/`multi_field_update` avoid those extra round-trips.

### 3. Create with Success Callback

**Pattern**: Use the block form of `create!` for additional operations:

```ruby
Customer.create!(email: 'new@example.com') do |customer|
  # This block only runs if creation succeeded
  customer.add_to_premium_group
  NotificationService.send_welcome_email(customer)
end
```

### 4. Command Replies Inside Transactions and Pipelines

Inside a `transaction`, `atomic_write` or `pipelined` block every command is
queued, and redis-rb returns a `Redis::Future` in place of its reply. The
Future's `value` is available only after the block completes. Each Familia
method handles this in one of three ways.

#### Pass through

A method that issues a command and only converts its reply returns that
command's `Redis::Future`. Converting means deserializing values, coercing a
number, or testing the reply (a count, a rank, a TTL) to answer a predicate.
After the block, the Future's `value` is the command's reply as redis-rb
returns it, without Familia's conversion. Outside a block the same methods
return what they always did, with one exception:
`HashKey#randfield(count, withvalues: true)` now returns `[field, value]` pairs.

```ruby
views = nil
empty = nil
user.atomic_write do
  user.name = 'Alice'                    # deferred scalar, queued as HMSET
  views = user.counts.increment('views') # Redis::Future
  empty = user.tags.empty?               # Redis::Future of SCARD
end
views.value        # => 6, HINCRBY replies with an Integer
empty.value.zero?  # => false, SCARD replies with the count
```

| Method | Future resolves to |
|---|---|
| `HashKey#[]`, `#values`, `#hgetall`, `#values_at`; `ListKey#range`, `#members`, `#pop`; `SortedSet#members`, `#range*`; `UnsortedSet#members`, `#sample` | the stored values, still serialized |
| `HashKey#randfield(count, withvalues: true)` | `[field, value]` pairs, the values still serialized |
| `empty?` on any collection | the count (HLEN, LLEN, SCARD, ZCARD) |
| The generated related-field predicates (`user.tags?`, `User.instances?`) | what the field's `empty?` resolves to: the count, or the raw stored string |
| `ListKey#member?`, `SortedSet#member?`, `#rank`, `#revrank` | the index or rank, or nil |
| The generated participation methods `in_<target>_<collection>?` and `score_in_<target>_<collection>` (`domain.in_customer_domains?(customer)`) | for `in_*?`, the ZRANK or LPOS index or nil on a sorted-set or list participation, and the SISMEMBER Boolean on a set one; for `score_in_*`, the Float score or nil |
| `DataType#exists?`, `Horreum.exists?`, `expires?`, `expired?` | the EXISTS count or the TTL in seconds |
| `HashKey#increment`, `#decrement`, `#incrbyfloat`; `SortedSet#score`, `#increment`, `#mscore` | the Integer or Float, which redis-rb converts itself |
| `Counter#value`, `StringKey#to_s`, `#to_i`, `#size`, `#empty?`, `JsonStringKey#to_s`, `#to_i`, `#to_f`, `#empty?` | the raw stored string, or nil |
| `Lock#release` | 1 when the lock was released, 0 otherwise |
| `Horreum.any?`, `.count`, `.keys_count`, `.keys_any?`, `.in_instances?`, `.multiget`, `.storage_inspect` | the ZCARD count, the KEYS array, the ZRANK reply, the MGET array or the HGETALL hash |
| `Migration::Registry#applied?`, `#applied_at`, `#all_applied`, `#metadata` | the ZSCORE, ZRANGE or HGET reply |

A `Redis::Future` is always truthy, so never test one inside the block. A
predicate or conditional write used as a condition there takes the true
branch whatever the reply turns out to be. That applies to the predicates in
the table (including `in_<target>_<collection>?`), to `HashKey#key?`,
`UnsortedSet#member?` and `indexed_in?`, and to the conditional writes
`HashKey#hsetnx`, `StringKey#setnx`, `JsonStringKey#setnx` and
`Lock#release`. For example,
`lock.release(token)` inside a transaction returns a truthy Future even when
`token` does not hold the lock. Read `future.value` after the block. Some
Futures resolve to a count rather than a Boolean: test
`empty.value.zero?`, not `empty.value`.

A top-level `transaction` or `pipelined` call returns a `MultiResult` whose
`results` holds each queued command's reply in queue order. It is empty when
a WATCH-guarded transaction aborted (see `MultiResult#aborted?`).
`atomic_write` and `Familia.atomic_write` return `true` or `false` instead,
so their callers read the values of the Futures they kept.

#### Fail fast

A method that needs a reply before it can finish raises
`Familia::OperationModeError` before queueing anything. That covers methods
that branch on a reply, raise from it, issue follow-up commands from it,
iterate, load records, or derive an answer from the reply's contents. It
also covers admission checks, whose answer tells the caller whether it may
proceed: whether it holds a lock, has claimed a value, or is under a limit.
Inside a block that answer would be a truthy Future, which admits the caller
before the server has answered.

- Iteration: `each`, `eachraw`, `eachraw_with_index`, `collectraw` and
  `selectraw` on every collection, `each_record`, and `scan_keys` with a block
- Reads that decide: `HashKey#fetch`, `HashKey#refresh!` and `#refresh`,
  `Horreum#refresh!` and `#refresh`, `extend_expiration`, `ttl_report`
- Loading: `find_by_dbkey`, `find_by_identifier` (`find_by_id`, `find`,
  `load`), `load_multi`, `load_multi_by_keys`, `all`, `find_by_objid`,
  `find_by_extid`, the index finders (`find_by_*`, `find_all_by_*`,
  `sample_from_*`), the participation readers (`*_ids`, `*_count`,
  `*_instances`, the participation predicate `<target>?` such as
  `user.project_team?`, `current_participations`, `position_in_*`,
  `*_with_permission`, `each_*_with_permission`), `current_indexings`
  and `relationship_status`
- Scans and maintenance: `scan_count` (`count!`), `scan_any?` (`any!`), the
  `audit_*`, `health_check`, `repair_*` and `rebuild_*` methods,
  `run_chores!`, and the `EnforceCollectionCaps` chore
- Migrations: `Migration::Base.run` and `.check_only`, and
  `Migration::Runner#run`, `#run_one`, `#rollback`, `#status` and `#pending`.
  The `Migration::Registry` methods that decide from a reply (`pending`,
  `status`, `record_rollback`, `schema_changed?`, `schema_drift`,
  `restore_backup`) raise when the registry's own client is a transaction or
  pipeline connection, so a registry built with its own client keeps working
  inside a block
- Writes that read first: the save methods in rule 1, `commit_fields`,
  `save_fields`, `multi_field_update`, `multi_field_fast_write`, class-level
  `destroy!`, instance `destroy!` on a class with instance-scoped indexes, the
  `guard_unique_*!` methods, and staged activation and unstaging
- Admission checks: `Lock#acquire`, `#locked?` and `#held_by?`,
  `Counter#increment_if_less_than`, `HashKey#claim_field`, and
  `claim_unique_*!`. `Lock#release` is deliberately not one. It passes its
  Future through so that it can be queued as the last command of the block
  the lock protects, and its script deletes the lock only if the token
  still holds it when the script runs
- Fast writers (`field!`) on fields backing a class-level index raise
  `Familia::IndexedFieldFastWriteError`, since the index claim cannot run
  there

Call these before or after the block.

#### Queue gated side effects

Some writes refresh the TTL only when they took effect: `HashKey#hsetnx`,
`JsonStringKey#setnx` and `#value` with a default, `ListKey#insert`, `#pushx`
and `#unshiftx`, and `SortedSet#popmin` and `#popmax`. Inside a block that
outcome is a Future, so the refresh is queued with the write. A key that the
queued write creates therefore keeps its TTL. When the write turns out to do
nothing, the refresh resets the TTL of a key that already exists, and a
missing key stays missing.

### 5. Handling Nested Transactions

**Behavior**: Familia uses reentrant transactions (see
`TransactionCore.execute_normal_transaction`). If you're already in a
transaction, a nested `transaction` call does not open a new MULTI/EXEC — it
yields the outer transaction's connection, so the nested block's commands are
queued into the outer MULTI and commit (or fail) with the outer EXEC.

Nesting itself never raises. The `Familia::OperationModeError` cases described
elsewhere in this document come from *what* runs inside a transaction (`save`,
`create!`, partial writes, and the other methods rule 4 lists) or from
connection handlers that do not support transactions, not from nested
`transaction` calls.

```ruby
Customer.transaction do |conn|
  # Outer transaction
  customer.increment(:counter)

  customer.transaction do |inner_conn|
    # Same connection as outer - no new MULTI/EXEC
    customer.decrement(:other_counter)
  end
end
```

## Examples

### Example 1: Correct Usage with Unique Constraints

```ruby
# Create with unique email constraint
begin
  customer = Customer.create!(email: 'user@example.com')
  puts "Created customer: #{customer.email}"
rescue Familia::RecordExistsError => e
  puts "Customer already exists: #{e.message}"
end
```

### Example 2: Atomic Multi-Object Updates

```ruby
# Save all objects first
order = Order.new(order_id: 'ORD-123')
order.save

inventory = Inventory.find('ITEM-456')

# Then use transaction for atomic updates
Order.transaction do
  order.hset(:status, 'confirmed')
  inventory.decrement(:quantity, 1)
  order.add_to_daily_orders
end
```

### Example 3: Bulk Creation Pattern

```ruby
# Claim each unique value outside the transaction. The claim is a
# server-side compare-and-set: the loser of a concurrent race raises
# Familia::RecordExistsError here, before anything is written.
customers = emails.map do |email|
  customer = Customer.new(email: email)
  customer.claim_unique_email_lookup!
  customer
end

# Then save atomically. The in-transaction index write is legal only
# because it re-affirms the claim taken above (see ADR-0002); without
# a claim, add_to_class_* raises Familia::OperationModeError.
Customer.transaction do
  customers.each do |customer|
    # Direct write operations only - no save!
    customer.hmset(customer.to_h_for_storage)
    customer.add_to_class_email_lookup
  end
end
```

### Example 4: Instance-Scoped Bulk Indexing

```ruby
# Instance-scoped indexes can be added within transactions
# Uniqueness validation is automatically skipped inside transactions
Company.transaction do
  employees.each do |employee|
    # Safe: validation skipped, direct index write only
    employee.add_to_company_badge_index(company)
  end
end
```

## Common Pitfalls

### Pitfall 1: Checking Existence in Transaction
```ruby
# ❌ WRONG
Customer.transaction do
  unless customer.exists?  # Returns Redis::Future, always truthy!
    customer.save
  end
end

# ✅ CORRECT
unless customer.exists?
  customer.save
end
```

### Pitfall 2: Creating in Transaction
```ruby
# ❌ WRONG
Customer.transaction do
  Customer.create!(email: 'test@example.com')  # Raises OperationModeError
end

# ✅ CORRECT
customer = Customer.create!(email: 'test@example.com')
customer.transaction do
  # Additional operations
end
```

## Migration Guide

If you have code that saves within transactions:

1. Move save operations outside the transaction
2. Use the transaction for atomic updates only
3. Validate constraints before entering the transaction
4. Use write-only operations inside the transaction

## See Also

- [Familia::OperationModeError](../lib/familia/errors.rb)
- [Transaction Implementation](../lib/familia/connection/transaction_core.rb)
- [Unique Index Guards](../lib/familia/features/relationships/indexing/unique_index_generators.rb)
