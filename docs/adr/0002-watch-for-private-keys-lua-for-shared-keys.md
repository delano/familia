# ADR-0002: WATCH for object-private keys, Lua CAS for shared keys

**Status:** accepted · 2026-07-25

## Context

Familia needs atomic check-then-write in two shapes. WATCH/MULTI/EXEC
(`TransactionCore.execute_watched_transaction` with `watch_keys:` +
`pre_check:`) aborts on any write to a watched *key*. When the key is shared by
unrelated writers — e.g. a class-level `unique_index` hash, one key holding
every field→id mapping — concurrent saves with no real conflict abort each
other, producing retry storms that scale with write volume. A server-side Lua
CAS checks and writes at *field* granularity in one eval, conflicting only on
genuine collisions, but cannot conditionally abort other commands queued in a
surrounding MULTI.

## Decision

Choose the primitive by key ownership:

- **Object-private key** (an instance's own dbkey): WATCH + pre_check, as in
  `save_if_not_exists!`. An abort there is a real conflict on that object.
- **Shared key** (class-level index hashes, any key many writers touch): Lua
  CAS at the point of the write. Run the claim *before* the save MULTI; the
  in-MULTI write then re-affirms an owned value idempotently.

Never WATCH a shared key. Never port a multi-command save body into Lua just to
avoid WATCH on a private key.

## Consequences

The two primitives coexist; each covers the case the other handles badly.
Closing the `unique_index` TOCTOU (guard-read before MULTI, blind HSET inside
it) means a Lua claim in the generated `update_in_class_*`/`add_to_class_*`
mutators, keeping `guard_unique_indexes!` as a fast-fail courtesy check. Known
cost: a claim that succeeds before an EXEC that dies on connection failure
leaves an orphan index entry until the next save cleans it via dirty tracking.
Lua enters an otherwise Lua-free gem — keep scripts small, single-key, and
tested.
