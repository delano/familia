Fixed
-----

- Partial write paths now maintain class-level indexes fail-closed.
  ``commit_fields``, ``save_fields``, and ``multi_field_update`` guard and
  claim class-level unique indexes *before* their transaction opens -- the
  same server-side Lua CAS that ``save`` uses, scoped to the fields being
  written -- and update the index entries inside the same ``MULTI`` as the
  hash write. Previously they wrote the hash and cleared dirty tracking
  without touching class-level indexes, so ``find_by_<field>`` kept resolving
  the old value and the freed value could not be reused. A constraint
  violation raises ``Familia::RecordExistsError`` before any hash command is
  queued; ``multi_field_update`` additionally rolls its in-memory assignments
  back, preserving its never-diverged contract. Indexes on fields outside a
  partial write are neither claimed nor re-affirmed, so unrelated claims
  survive it. Timestamps are untouched -- unlike ``save``, a partial write
  still does not bump ``created``/``updated``. #308

- Fast writers (``field!``) on a field backing a class-level index now claim
  and update the index before the ``HSET`` instead of leaving the entry
  stale. A losing claim raises ``Familia::RecordExistsError`` with the hash
  and in-memory state untouched. For ``multi_index``-backed fields the update
  is add-only, matching save. #308

Changed
-------

- ``multi_field_fast_write`` raises ``Familia::IndexedFieldFastWriteError``
  (new, ``< PersistenceError``, exposes ``field``/``index_name``) when any
  written field backs a class-level index (``unique_index`` or
  ``multi_index``) -- previously it wrote the hash and silently skipped the
  index. Its single-``HMSET`` contract leaves no room for the
  out-of-transaction claim ADR-0002 requires, so the write is refused before
  anything is touched. The check is local metadata only; non-indexed fields
  keep the one-round-trip behavior unchanged. Use ``multi_field_update``,
  ``save_fields``, or ``save`` for indexed fields. #308

- ``field!`` on a class-indexed field raises
  ``Familia::IndexedFieldFastWriteError`` inside a caller's transaction or
  pipeline, where the claim's CAS verdict would come back as a ``Future`` --
  previously it queued the ``HSET`` and left the index stale. It also now
  refuses an unsaved record for such fields (``Familia::PersistenceError``,
  "Call #save first"), consistent with every other index writer. #308

Removed
-------

- ``Familia::Horreum::Definition#define_fast_writer_method``: dead duplicate
  of ``FieldType#define_fast_writer`` with zero callers. #308

AI Assistance
-------------

- AI extended the #353 claim machinery to the partial writers: extracted
  ``prepare_for_partial_write`` (guard + claim scoped to written fields, no
  timestamp mutation), added ``only:`` filters to the guard/claim/index-update
  primitives with a per-index ledger reset so partial writes do not wipe
  unrelated claims, restructured ``multi_field_update`` to run setters before
  the claim with snapshot/rollback of in-memory state, and taught the
  generated ``field!`` writers to resolve index participation lazily per
  runtime class. Added tryouts covering index add/remove per write path,
  fail-closed conflicts with rollback, transaction/pipeline refusal, and
  timestamp non-mutation; updated the transaction-safety and indexing guides
  with a per-write-path maintenance table.
