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

## Implementation notes

Implemented for `unique_index` in `HashKey#claim_field` / `#release_field`
(`lib/familia/data_type/types/hashkey.rb`), driven by
`Horreum#claim_unique_indexes!` from `prepare_for_save`. Three things the
decision above did not anticipate, settled during implementation:

- **The guard is load-bearing, not courtesy.** With more than one unique index
  on a class, claiming index A and then colliding on index B strands A's value
  on a record that never saves. `guard_unique_indexes!` reads *every* index
  before *any* claim is written, so the common case fails before the first
  write; for the residual race, `claim_unique_indexes!` releases the claims it
  *created* (not ones the record already owned) before re-raising.
- **The release side needs the same protection.** An unconditional `HDEL` lets a
  stale in-memory value evict a claim another record now owns. Unlike the claim,
  an ownership-checked delete needs no return value to decide anything, so it
  *can* be queued inside the MULTI — which is what `destroy!` and the old-value
  removal in `update_in_class_*` do.
- **The in-MULTI HSET asserts a prior claim.** It is only sound as a
  re-affirmation, so the mutators raise `OperationModeError` when called inside a
  caller-opened transaction with no claim on record, rather than silently
  reverting to the blind write.
