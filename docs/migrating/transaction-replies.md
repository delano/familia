# Migrating: Command Replies Inside Transactions and Pipelines

Inside `transaction`, `atomic_write` and `pipelined` blocks, redis-rb returns a
`Redis::Future` in place of each command reply. Familia methods now handle that
in one of three ways, described in rule 4 of
[Transaction Safety](../reference/transaction_safety.md): they return the
command's Future, they raise `Familia::OperationModeError` before queueing
anything, or they queue a TTL refresh together with the write. Outside a block
every method returns what it did before, with one exception:
`HashKey#randfield(count, withvalues: true)` now returns `[field, value]` pairs.
It used to return `[[[field, raw_value], nil]]` when one pair came back and
raise `ArgumentError` for more.

Most of the affected calls used to raise `NoMethodError`,
`Familia::ConflictingContextError` or a spurious `Familia::RecordExistsError`
inside a block, so code could not have relied on them. The calls below
behaved differently, and code that uses them inside a block needs a change.

## Partial writes inside a transaction now raise

Inside a caller's `transaction`, `multi_field_update` and
`multi_field_fast_write` queued their write into the outer MULTI, and it
committed with the outer EXEC. They now raise `Familia::OperationModeError`
before changing anything, in memory or in the database. `commit_fields` and
`save_fields` raised `NoMethodError` there and now raise
`Familia::OperationModeError` too.

Write the fields before the block, or move the whole change into
`atomic_write`, which writes the scalar fields and the collection commands in
one MULTI/EXEC:

```ruby
# Before: the field write committed with the outer EXEC
user.transaction do
  user.multi_field_update(name: 'Alice')
  user.tags.add('renamed')
end

# After: one MULTI/EXEC for the fields and the collection
user.atomic_write do
  user.name = 'Alice'
  user.tags.add('renamed')
end

# Or, when the two writes need not be atomic
user.multi_field_update(name: 'Alice')
user.tags.add('renamed')
```

## `extend_expiration` inside a block now raises

Inside a transaction or pipeline, `extend_expiration` returned `false` and left
the TTL unchanged. It now raises `Familia::OperationModeError`, because it
computes the new TTL from the current one. Call it before or after the block.

## Lock ownership checks inside a block now raise

Inside a transaction or pipeline, `Lock#held_by?` returned `false`, even for
the token that holds the lock, and `Lock#locked?` raised `NoMethodError`. Both
now raise `Familia::OperationModeError`. Check ownership before the block.

`Lock#release` inside a block returned `false`, even when the queued script
released the lock. It now returns the EVAL `Redis::Future`. The Future is
truthy whether or not the lock was released, so do not test it inside the
block. Read its value after the block:

```ruby
raise LockLost unless lock.held_by?(token)

released = nil
Familia.transaction do
  # ... the writes the lock protects ...
  released = lock.release(token)
end
released.value # => 1 when this token released the lock, 0 otherwise
```

## `current_indexings` inside a block now raises

Inside a transaction or pipeline, `current_indexings` reported every
class-level index whose field was set, whether or not the record was in the
index. It now raises `Familia::OperationModeError`, and so does
`relationship_status`. Call them outside the block.

## `Migration::Registry#applied?` returns a Future inside a block

Inside a transaction or pipeline, `Migration::Registry#applied?` returned
`true` for every migration. It now returns the ZSCORE `Redis::Future`, which
resolves to the score or `nil` after the block. The Future is truthy, so read
its value after the block rather than testing it inside.

A registry created without `redis:` no longer keeps the first connection it
resolves. It calls `Familia.dbclient` once per method call, so without a
connection provider each call opens a new connection. Pass `redis:` to
`Familia::Migration::Registry.new` to reuse one client.

## Futures are truthy

These methods raised `NoMethodError` inside a block and now return the
command's `Redis::Future`: `empty?` on collections and on `StringKey`,
`Counter` and `JsonStringKey`, the generated related-field predicates such
as `user.tags?`, `ListKey#member?` and `SortedSet#member?`, and the generated
participation methods `score_in_<target>_<collection>` and
`in_<target>_<collection>?` on a sorted-set or list participation. Rule 4 of
[Transaction Safety](../reference/transaction_safety.md) lists what each
Future resolves to.

Some methods already returned their Future inside a block and are unchanged:
`exists?`, `HashKey#key?`, `UnsortedSet#member?`, `indexed_in?`,
`HashKey#hsetnx`, `StringKey#setnx`, `JsonStringKey#setnx`, and
`in_<target>_<collection>?` on a set participation. `Lock#release`
changed from `false` to a Future; see the Lock section above.

A Future is always truthy, so a predicate or conditional write tested inside
the block takes the true branch whatever the reply turns out to be. Read the
Future's value after the block.

## `HashKey#hsetnx` and `ListKey#insert` inside a block now refresh the TTL

Inside a transaction or pipeline, `HashKey#hsetnx` and `ListKey#insert` did
not refresh the key's TTL. They now queue the refresh with the write, whether
or not the write turns out to take effect. When `hsetnx` finds the field
already set, or `insert` does not find its pivot, the TTL of the existing hash
or list is reset to the configured default. Outside a block both refresh only
when the write takes effect, so call them outside the block if an existing key
must keep its remaining TTL.
