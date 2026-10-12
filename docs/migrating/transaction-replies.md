# Migrating: Command Replies Inside Transactions and Pipelines

Inside `transaction`, `atomic_write` and `pipelined` blocks, redis-rb returns a
`Redis::Future` in place of each command reply. Familia methods now handle that
in one of three ways, described in rule 4 of
[Transaction Safety](../reference/transaction_safety.md): they return the
command's Future, they raise `Familia::OperationModeError` before queueing
anything, or they queue a write's TTL refresh with it. Outside a block
every method returns what it did before, with one exception:
`HashKey#randfield(count, withvalues: true)` now returns `[field, value]` pairs.
It used to return `[[[field, raw_value], nil]]` when one pair came back and
raise `ArgumentError` for more.

Most of the affected calls used to raise an error inside a block
(`NoMethodError`, `TypeError`, `Familia::SerializerError`,
`Familia::ConflictingContextError` or a spurious `Familia::RecordExistsError`),
so code could not have relied on them. The calls below behaved differently,
and code that uses them inside a block needs a change.

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

## Unstaging inside a transaction now raises

Inside a caller's `transaction`, `unstage_<name>_instance` queued the staging
set ZREM and the staged model's `destroy!` into the outer MULTI, and they
committed with the outer EXEC. It returned `true` whether or not the staged
model existed. It now raises `Familia::OperationModeError` before queueing
anything, because it checks that the staged model exists before destroying it
and reports that outcome. Call it before or after the block:

```ruby
# Before: the unstage committed with the outer EXEC
org.transaction do
  org.unstage_members_instance(invitation)
  org.revoked_invitations.add(invitation.objid)
end

# After: two separate writes
org.unstage_members_instance(invitation)
org.revoked_invitations.add(invitation.objid)
```

The other staged participation methods and the add and remove methods of a
`through:` participation raised an error inside a block before and still do,
now `Familia::OperationModeError` before queueing anything.

## `extend_expiration` inside a block now raises

Inside a transaction or pipeline, `extend_expiration` returned `false` and left
the TTL unchanged. It now raises `Familia::OperationModeError`, because it
computes the new TTL from the current one. Call it before or after the block.

## Lock ownership checks inside a block now raise

Inside a transaction or pipeline, `Lock#held_by?` returned `false`, even for
the token that holds the lock, and `Lock#locked?` raised `NoMethodError`. Both
now raise `Familia::OperationModeError`. Check ownership before the block.

`Lock#release` inside a block returned `false`, even when the queued script
released the lock. It now returns the EVAL `Redis::Future`, which resolves to
`true` when the script released the lock and `false` otherwise, the same
Boolean the method returns outside a block. The Future itself is truthy
whether or not the lock was released, so do not test it inside the block.
Read its value after the block:

```ruby
released = nil
Familia.transaction do
  ledger.push('debit')
  released = lock.release(token)
end
raise LockLost unless released.value
```

A release queued in a block does not guard the other commands in that block.
The script checks the token when it runs at EXEC, and its `false` reply does
not stop the other queued commands. If the lock expired or passed to another
holder before EXEC, `ledger.push` above still commits, and `released.value`
only reports the loss afterwards. A `held_by?` check before the block does
not close that gap. When the writes must not commit without the lock, WATCH
the lock key and check the token with a GET on the same connection before
the MULTI, so that EXEC aborts if the lock changes, or check the token and
write in one server-side script. `Lock#held_by?` resolves its own
connection, so it cannot serve as the check under WATCH.

The [Redis transactions documentation](https://redis.io/docs/latest/develop/using-commands/transactions/)
states that "if the EXEC command is called, all the operations are
performed" and that "Redis does not support rollbacks of transactions". For
WATCH it states: "If at least one watched key is modified before the EXEC
command, the whole transaction aborts", where modifications include those
"by Redis itself, like expiration or eviction"; it also notes that "In Redis
versions before 6.0.9, an expired key would not cause a transaction to be
aborted." Familia's [ADR-0002](../adr/0002-watch-for-private-keys-lua-for-shared-keys.md)
likewise records that a server-side Lua check "cannot conditionally abort
other commands queued in a surrounding MULTI."

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

A registry created without `redis:` no longer keeps a connection resolved
inside a Familia transaction or pipeline block. Inside such a block it uses
the block's connection for that call only. Outside a block it keeps the
first connection it resolves, as before.

## `as_json` on a scalar inside a block now raises

Inside a transaction or pipeline, `as_json` on a `StringKey`, `JsonStringKey`
or `Lock` returned the GET `Redis::Future`. It now raises
`Familia::OperationModeError`, like Ruby's other conversion methods (`to_s`,
`to_i`, `to_f`, `to_a` and `to_json`), which raised `NoMethodError` or
`Familia::SerializerError` there. Call `value` inside the block to get the GET
Future, and convert its value after the block:

```ruby
nick = nil
user.transaction do
  nick = user.nick.value
end
nick.value # => the raw stored string
```

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

## Conditional writes inside a block refresh the TTL as they do outside it

Inside a transaction or pipeline, `HashKey#hsetnx` and `ListKey#insert` did
not refresh the key's TTL, so a hash or list they created there had none.
`JsonStringKey#setnx`, and `JsonStringKey#value` with a default, reset the
key's TTL to the configured default even when the key was already set, so a
plain read with a default shortened an extended TTL.

All four now queue one EVAL that runs the write and refreshes the TTL only
when the write takes effect, the same rule they follow outside a block. A
field or key that is already set, or a missing pivot, leaves the existing
key's TTL unchanged. `hsetnx` and `setnx` still return a Future that resolves
to `true` or `false`, and `insert` one that resolves to the list length, `-1`
or `0`. Inside a block the server sees an EVAL in place of HSETNX, SETNX or
LINSERT, which shows in `MONITOR` output and command logs.

`JsonStringKey#setnx` and `JsonStringKey#value` with a default previously
added two replies to `MultiResult#results` when the key had a TTL: the
SETNX Boolean, then the EXPIRE reply. They now add one, the EVAL reply,
which is the same `true` or `false`. Every reply queued after one of these
calls moves up one index, so code that reads `MultiResult#results` by
position needs its indexes updated. `hsetnx` and `insert` still add one
reply each, as before.

```ruby
result = Familia.transaction do
  account.settings.value          # json_string with a default and a TTL
  account.settings.setnx({ 'theme' => 'dark' })
end

# Before: [false, true, "{\"theme\":\"light\"}", false, true]
# After:  [false, "{\"theme\":\"light\"}", false]
result.results
```
