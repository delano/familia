# Rebuild memory incident: class-level unique indexes

## Scope and status

This is a focused diagnosis of memory growth observed while a downstream model
runs a generated `rebuild_<unique_index>` method on the class-level
`via_instances` path. It is a diagnosis and implementation plan; it does not
change runtime behaviour.

**This is not issue #309.** #309 concerns the generated
`<collection>_with_permission` query and is recorded as fixed in the
[Familia memory audit](memory-audit.md), under “Issue #309 — focused diagnosis
and fix design.”

The broader [memory audit](memory-audit.md) is the canonical evidence record for
other Ruby-process risks, Redis-side orphan types, and rejected hypotheses. This
incident document records only the rebuild path and its proposed resolution.

## Symptom and classification

A rebuild creates two distinct memory effects that must not be conflated:

| Effect | Location | Classification |
|---|---|---|
| Expired records leave `instances` and class-level `unique_index` entries behind | Redis `used_memory` | Unbounded growth |
| Rebuild loads every `instances` member into Ruby before batching | Ruby RSS | Transient O(N) high-water mark |
| A failed swap preserves a full temporary index key | Redis `used_memory` | Resolved: bounded to the diagnostic window |

`try/investigation/memory_leak_proof.rb` exercises these three effects against a
live Redis instance.

## Causal chain

1. Every `Horreum` subclass declares an `instances` sorted set
   (`lib/familia/horreum.rb:176`). On each save, persistence updates both this
   set and class-level indexes (`lib/familia/horreum/persistence.rb:944,947`).
2. With expiration enabled, a model's main hash can expire without calling
   `destroy!`. `destroy!` is the only removal path for these shared collection
   entries (`lib/familia/horreum/persistence.rb:585,588`). Redis TTL applies to
   an entire key, not individual ZSET members or HASH fields.
3. Ongoing writes refresh the whole-key TTL on `instances` and `unique_index`,
   so expired records leave entries that accumulate. If writes instead stop for
   longer than the TTL, the shared key can expire wholesale, including entries
   for live objects.
4. `rebuild_<unique_index>` follows `rebuild_via_instances`, which currently
   calls `instances.members.each_slice(batch_size)`
   (`lib/familia/features/relationships/indexing/rebuild_strategies.rb:108`).
   `members` materializes the full ZSET before `each_slice` can limit a batch.

The visible Ruby RSS spike is therefore proportional to the full, potentially
ghost-bloated `instances` set—not the number of live records or `batch_size`.

## Additional rebuild paths

- `rebuild_via_participation` has the same `.members.each_slice` materialization
  pattern (`rebuild_strategies.rb:226`).
- Class-level and instance-scoped multi-index rebuilds also retain every loaded
  object in `cached_objects` for the full rebuild
  (`multi_index_generators.rb:232,235,498`). Their documented `batch_size:`
  controls Redis I/O, not total Ruby memory.
- Temporary swap keys are now bounded (`lib/familia/atomic_operations.rb`).
  `with_rebuild` gives the temporary key a TTL of `DEFAULT_REBUILD_TTL` (300
  seconds), refreshed once per batch, and deletes it when the rebuild block
  raises. On a non-"no such key" swap error, `atomic_swap` retains the
  temporary key for `preserve_for` seconds (default 3600) rather than
  indefinitely, so a failed rebuild no longer leaves a full-index-sized HASH
  behind. Key-name collisions between rebuilds started in the same second are
  resolved: `build_temp_key` appends a 64-bit random nonce to the timestamp
  suffix, and a per-index lock prevents concurrent rebuilds of the same index
  entirely. `atomic_swap` fails closed: it raises on an error object or aborted
  transaction in the swap results, and a `RENAME` reporting "no such key" after
  the temporary key passed the `EXISTS` check raises rather than reporting
  success over a stale live index.

## Implementation plan

1. **Stream identifiers for unique-index rebuilds.** Replace `.members` with
   `instances.each(batch_size: ...)`, buffer only one batch, then call
   `load_multi` and write that batch. `SortedSet#each` uses `ZSCAN` when no score
   bounds are supplied (`lib/familia/data_type/types/sorted_set.rb:253-324`).
   ZSCAN may repeat members and is unordered; HSET is idempotent, but progress
   reporting must not promise an exact member count.
2. **Remove whole-rebuild object retention from multi-index rebuilds.** Discover
   field values and rebuild incrementally, or introduce a disk/Redis-backed
   intermediate representation. Do not retain `cached_objects` for reuse.
3. **Make temporary rebuild keys safe.** Done. `build_temp_key` appends a
   64-bit random nonce to the timestamp suffix. `AtomicOperations.with_rebuild`
   holds a per-index lock at `<final_key>:rebuild-lock`, applies a bounded TTL
   to the temporary key while the rebuild is in progress, refreshes it once per
   batch through the yielded `touch`, and deletes the temporary key if the
   block raises. A rebuild that finds the lock held raises
   `Familia::RebuildInProgressError` rather than waiting. The lock is refreshed
   by compare-and-extend, so a rebuild whose batch overran the lock TTL cannot
   extend a lock a successor has taken; it raises
   `Familia::RebuildLockLostError` at the next `touch` or immediately before the
   swap, drops its own temporary key, and leaves the live index untouched. On
   swap failure `atomic_swap` logs the key and retains it only for
   `preserve_for` seconds. `AtomicOperations.sweep_orphaned_temp_keys` clears
   legacy `*:rebuild:*` keys that have no TTL and are older than the window; it
   skips any candidate whose index has a live `:rebuild-lock`, and lock keys do
   not match its pattern. All four rebuild call sites (`rebuild_instances` and
   the three indexing strategies) go through `with_rebuild`.
4. **Address expired-index entries separately.** A streaming rebuild limits Ruby
   peak memory but cannot remove persistent ghost entries by itself. Add an
   expiry-aware reaper or document and schedule the existing repair/audit tooling
   for models that combine expiration with class-level indexes.

## Acceptance criteria

- A large `instances` set can rebuild with Ruby memory proportional to one batch,
  apart from the output index being built in Redis.
- A rebuild remains correct when scans are unordered or repeat members.
- No temporary rebuild key remains indefinitely after an interrupted or failed
  rebuild. Met: temporary keys carry a TTL during the rebuild and a bounded
  retention window after a failed swap.
- Expiring models have an explicit, tested process for pruning stale `instances`
  and class-index entries.
- Tryouts cover large collections, duplicate scan results, missing records,
  interrupted swaps, temporary key naming, and lock contention between
  concurrent rebuilds of the same index.

## Verification

Run the focused proof against Redis:

```sh
FAMILIA_TEST_URI=redis://127.0.0.1:6379 ruby try/investigation/memory_leak_proof.rb
```

After implementation, add or update targeted tryouts before relying on the
proof as a regression test for streaming behaviour.
