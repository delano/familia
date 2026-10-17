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
raise `ArgumentError` for more. Two persistence effects changed outside a
block too: `HashKey#hsetnx` now refreshes the hash's TTL after setting a new
field (see the last section), and `JsonStringKey#empty?` on a key declared
with `default:` no longer writes the default to a missing key or refreshes
the TTL; it reads with GET only.

Most of the affected calls used to raise an error inside a block
(`NoMethodError`, `TypeError`, `Familia::SerializerError`,
`Familia::ConflictingContextError` or a spurious `Familia::RecordExistsError`),
so code could not have relied on them. The calls below behaved differently,
and code that uses them inside a block needs a change.

## familia requires redis-rb 5.4 or later

familia's gemspec now declares `redis` `>= 5.4, < 6.0` (it was `>= 5.0`).
`Lock#release`, and inside a block `HashKey#hsetnx`, `JsonStringKey#setnx`
and `JsonStringKey#value` with a default, pass a block to `Redis#call` that
turns the script's `1` or `0` reply into `true` or `false`. redis-rb's
changelog for 5.4.0 says: "`Redis#call` now accept a block, allowing to use
`Redis` instances where `RedisClient` is expected." Versions 5.0 to 5.3
drop the block, so with them `Lock#release` returned `0`, which is truthy,
for a release that failed.

A bundle that pins `redis` below 5.4 no longer resolves with this familia.
Update it:

```ruby
# Gemfile
gem 'redis', '>= 5.4', '< 6.0'
```

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

## `add_to_*` with no field value inside a pipeline now raises

Inside a pipeline, the instance-scoped `add_to_<scope>_<index>` method of a
`unique_index` returned `nil` and wrote nothing when the indexed field was
`nil`. It now raises `Familia::OperationModeError` before queueing anything,
as it does inside a pipeline when the field is set (where it raised a
spurious `Familia::RecordExistsError`). Outside a block and inside a
transaction it still returns `nil` for a `nil` field. Call it before or after
the pipeline.

## `Migration::Registry` without `redis:` uses the block's connection

`Migration::Registry#client` without `redis:` now returns the current
transaction or pipeline connection inside a Familia block, without keeping
it. It used to keep the first connection it resolved, whatever that was.
`Migration::Runner` builds its default registry without `redis:`, so a
registry first used outside a block kept a plain connection for life, and
inside a later block its commands ran at once, outside the MULTI: every
registry method returned its usual value. Inside a block such a registry now
returns the `Redis::Future` from `applied?`, `applied_at`, `all_applied` and
`metadata`, queues `record_applied` with the block and returns its Future,
and raises `Familia::OperationModeError` from `pending`, `status`,
`record_rollback`, `schema_changed?`, `schema_drift` and `restore_backup`.
The `applied?` Future resolves to the ZSCORE score or `nil` after the block
and is truthy, so read its value after the block rather than testing it
inside.

A registry first used inside a block returned `true` from `applied?` for
every migration, and kept the block's connection after the block completed,
so a later `record_applied` returned a Future and wrote nothing. It now
behaves inside the block as above and resolves a plain connection after it.
Outside a block `client` still keeps the first connection it resolves.

The block's connection is on the logical database the block was opened on.
Inside a block every `Familia.dbclient` lookup returns that connection,
whatever database is asked for, so a registry used inside
`Order.transaction`, where `Order` declares `logical_database 7`, writes
its records to database 7. `applied?` outside the block reads the
registry's own database and does not find them, and the runner treats the
migration as pending. A registry first used outside the block kept its own
connection before this change, so its records stayed on its database. Pass
a client to keep that:

To keep a registry on its own connection inside any block, as before, pass
one:

```ruby
# Before: first use outside the block kept a plain connection
registry = Familia::Migration::Registry.new
registry.applied?('20260101_add_status')   # => false, plain connection kept
Familia.transaction do
  registry.applied?('20260101_add_status') # => false, ran at once
end

# After: pass a client to keep that behaviour
registry = Familia::Migration::Registry.new(redis: Familia.create_dbclient)
Familia.transaction do
  registry.applied?('20260101_add_status') # => false, ran at once
end
```

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
not refresh the key's TTL, so a hash that `hsetnx` created there had none,
and a successful `insert` left the list's TTL as it was.
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

Because they send EVAL, these four calls need scripting permission inside a
block: the ACL `@scripting` category, or at least `+eval`. Outside a block
they still send the plain command and need no scripting permission. Where
scripting is denied, the server answers the EVAL with `NOPERM` and Familia
raises `Redis::PermissionError`. In a transaction or `atomic_write` nothing
in the block is applied. In a pipeline the other commands still run and the
error is raised after the pipeline. `JsonStringKey#value` on a `json_string`
declared with `default:` counts, so a plain read can trigger this.

When the `json_string` has a default expiration (a positive
`default_expiration`, its own or inherited from the parent, and no
`no_expiration: true`), `JsonStringKey#setnx` and `JsonStringKey#value`
with a default previously added two replies to `MultiResult#results`: the
SETNX Boolean, then the EXPIRE reply. They now add one, the EVAL reply,
which is the same `true` or `false`. Every reply queued after one of these
calls moves up one index, so code that reads `MultiResult#results` by
position needs its indexes updated. Without a default expiration no EXPIRE
was queued, so these calls added one reply before and still do; the key's
current TTL plays no part. `hsetnx` and `insert` still add one reply each,
as before.

```ruby
result = Familia.transaction do
  account.settings.value          # json_string with a default and a default expiration
  account.settings.setnx({ 'theme' => 'dark' })
end

# Before: [false, true, "{\"theme\":\"light\"}", false, true]
# After:  [false, "{\"theme\":\"light\"}", false]
result.results
```

`ListKey#pushx` and `#unshiftx` on a list with a default expiration added one
reply, the RPUSHX or LPUSHX count, and now add two: the count, then the
EXPIRE reply, because they queue the TTL refresh inside a block instead of
skipping it. The index of every reply queued after one of them increases by
one. `SortedSet#popmin` and `#popmax` raised `NoMethodError` inside a block;
they now add the ZPOPMIN or ZPOPMAX reply and, on a sorted set with a default
expiration, the EXPIRE reply after it. Without a default expiration each of
the four adds one reply.

```ruby
result = Familia.transaction do
  queue.items.pushx('a')   # list with a default expiration, one element before
  queue.items.push('b')
end

# Before: [2, 3, true]
# After:  [2, true, 3, true]
result.results
```

## `HashKey#hsetnx` outside a block now sets the TTL

Outside a block, `HashKey#hsetnx` never refreshed the key's TTL: it compared
the HSETNX reply with `1`, and redis-rb returns `true` or `false`. It now
applies the hash's default expiration (its own `default_expiration:` option,
or the parent's `default_expiration`) after setting a new field, as `[]=`
does, and leaves the TTL unchanged when the field was already set. A hash
with a default expiration that was only ever written with `hsetnx` had no
TTL and never expired; it now expires. To keep such a hash, declare it with
`no_expiration: true`, or call `persist` after the write:

```ruby
class Worker < Familia::Horreum
  feature :expiration
  default_expiration 3600
  identifier_field :wid
  field :wid
  hashkey :claims                      # Before: TTL -1 after hsetnx. After: 3600
  hashkey :leases, no_expiration: true # TTL -1 before and after
end

worker.claims.hsetnx('job-1', 'a')
worker.claims.persist                  # TTL -1 again
```
