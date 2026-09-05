Security
--------

- Made ``AtomicOperations.build_temp_key`` append a 64-bit random nonce to the
  timestamp suffix (``<key>:rebuild:<timestamp>:<16 hex>``) so concurrent
  rebuilds of the same index started within one second no longer share a
  temporary key.
- Index rebuilds now hold a per-index advisory lock at
  ``<final_key>:rebuild-lock`` for the duration of the rebuild, so two rebuilds
  of the same index cannot run at once and swap a stale snapshot over a newer
  one.
- Temporary rebuild keys carry a TTL that is refreshed once per batch, and a
  failed swap now retains the temporary key for a bounded diagnostic window
  (``preserve_for``, default 3600 seconds) instead of indefinitely.
- The rebuild lock is refreshed by compare-and-extend, so a rebuild that
  stalled past the lock TTL can no longer extend a lock another rebuild has
  taken over. It raises ``Familia::RebuildLockLostError`` at the next batch or
  immediately before the swap, deletes its own temporary key, and leaves the
  live index untouched.
- ``AtomicOperations.atomic_swap`` fails closed. It inspects the transaction
  results and raises on any error object or aborted transaction, and a
  ``RENAME`` reporting "no such key" after the temporary key passed the
  ``EXISTS`` check now raises instead of returning as if the swap succeeded.
  The live index is never replaced by a partial rebuild, and a lost rebuild is
  never reported as a successful one.

Added
-----

- Added ``Familia::AtomicOperations.with_rebuild(final_key, redis, ttl:
  DEFAULT_REBUILD_TTL, preserve_for: DEFAULT_PRESERVE_TTL)``, which yields
  ``(temp_key, touch)`` and owns the rebuild lock, the bounded-TTL temporary
  key, the atomic swap, and cleanup. Raises
  ``Familia::RebuildInProgressError`` when the lock is already held.
- Added ``Familia::AtomicOperations.sweep_orphaned_temp_keys(redis, pattern:
  '*:rebuild:*', older_than: DEFAULT_PRESERVE_TTL, dry_run: false)``, which
  deletes temporary rebuild keys that have no TTL and are older than the
  window. It skips any candidate whose index has a live ``:rebuild-lock``, and
  never matches lock keys itself.
- Added ``Familia::RebuildInProgressError`` (a ``Familia::PersistenceError``)
  with a ``#key`` reader.
- Added ``Familia::RebuildLockLostError``, a subclass of
  ``Familia::RebuildInProgressError``, raised when a rebuild discovers another
  rebuild took over its lock.
- Added ``Familia::AtomicOperations::DEFAULT_REBUILD_TTL`` (300) and
  ``DEFAULT_PRESERVE_TTL`` (3600).

Changed
-------

- ``rebuild_instances`` and the ``rebuild_via_instances``,
  ``rebuild_via_participation``, and ``rebuild_via_scan`` strategies now run
  under ``with_rebuild``. A rebuild of an index that is already being rebuilt
  raises ``Familia::RebuildInProgressError`` immediately instead of running
  concurrently; rebuilds never wait or retry.
- ``AtomicOperations.atomic_swap`` now issues ``RENAME`` and ``PERSIST`` in one
  transaction, so the live index does not inherit the temporary key's TTL. It
  accepts a ``preserve_for:`` keyword.
- ``AtomicOperations.with_rebuild`` raises ``Familia::OperationModeError`` when
  called inside an enclosing ``Familia.transaction`` or pipeline, because the
  lock ``SET NX`` would only be queued there and could not enforce exclusion.

AI Assistance
-------------

- The lock, TTL, and sweep design and the accompanying tests were developed
  with AI assistance.
