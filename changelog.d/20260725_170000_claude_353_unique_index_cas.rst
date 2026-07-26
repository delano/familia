Fixed
-----

- ``unique_index`` no longer has a TOCTOU race between its uniqueness guard and
  the index write. Previously ``guard_unique_*!`` read the index before the save
  ``MULTI`` and the index ``HSET`` inside it was blind, so two concurrent saves
  of the same value could both pass the guard and the later write would silently
  overwrite the earlier one -- leaving two records believing they owned the
  value. The invariant is now enforced server-side: a single-key Lua
  compare-and-set claims the value before the transaction opens, and the
  in-``MULTI`` ``HSET`` only re-affirms a claim this record already holds. The
  loser of a race raises ``Familia::RecordExistsError`` with ``existing_id``
  instead of overwriting. Field-granular, so unrelated saves of the same class
  never contend -- unlike ``WATCH``, whose per-key granularity would serialize
  every writer through one hot index key. #353

- ``remove_from_class_*`` and the old-value removal in ``update_in_class_*`` no
  longer issue a blind ``HDEL``. A record holding a stale in-memory field value
  could delete an index entry another record had since legitimately claimed --
  the release-side twin of the same shared-key overwrite. Both now use an
  ownership-checked delete that leaves another owner's entry intact. #353

Added
-----

- ``Familia::HashKey#claim_field`` and ``#release_field``: server-side
  compare-and-set / compare-and-delete on a single hash field. ``claim_field``
  returns ``:created`` when the field was unclaimed, ``:owned`` when it already
  held an equivalent value, or the conflicting value when another owner holds
  it; it raises ``Familia::OperationModeError`` inside a transaction or pipeline,
  where its verdict would only be a ``Future``. ``release_field`` deletes only
  when the caller owns the value and is safe to queue inside a ``MULTI``. Both
  touch exactly one key, so they work unchanged under Redis Cluster. Values
  written by pre-2.10.0 unique indexes (JSON-encoded identifiers such as
  ``"\"u1\""``) count as owned and are normalized to the canonical form in
  place. #353

- Generated per-index ``claim_unique_<index>!`` and ``release_unique_<index>!``
  instance methods, plus a private ``claim_unique_indexes!`` (alongside the
  existing ``guard_unique_indexes!``) that ``prepare_for_save`` now runs after
  the guard. When a class declares several unique indexes and a later one
  collides, claims *created* earlier in the same run are released before the
  error propagates, so a value is never stranded on a record that never got
  saved. Entries the record already owned are left intact. #353

Changed
-------

- ``add_to_class_<index>`` and ``update_in_class_<index>`` for a ``unique_index``
  now raise ``Familia::OperationModeError`` when called inside a transaction the
  caller opened without first claiming the value. The in-``MULTI`` ``HSET`` is
  only sound as a re-affirmation of an existing claim; without one it is the
  blind write this change removes. All ``save`` paths (``save``,
  ``save_if_not_exists!``, ``atomic_write``, ``Familia.atomic_write``) claim via
  ``prepare_for_save`` and are unaffected. Instance-scoped (``within:``) unique
  indexes keep the documented in-transaction escape hatch but now warn that the
  write is unenforced. #353

- ``guard_unique_indexes!`` is retained and is load-bearing rather than
  redundant: it checks every unique index *before* any claim is written, so the
  common collision fails without touching the index at all. It remains a
  fast-fail read; ``claim_unique_indexes!`` is the enforcement. #353

- Callers of ``remove_from_class_*`` (including ``remove_from_all_indexes`` and
  the class-level ``destroy!`` cleanup) no longer evict an index entry that
  points at a *different* identifier; the delete is now a no-op in that case
  rather than removing another record's live entry. Both built-in callers load
  the record's stored values immediately beforehand, so a no-op there means the
  index was already inconsistent. Code that relied on the previous blind ``HDEL``
  to clear wrong-owner entries should use the repair/rebuild APIs
  (``rebuild_<index>``, ``repair_*``), which write the index directly. #353

AI Assistance
-------------

- AI implemented the Lua CAS design recorded in ADR-0002, adding
  ``claim_field``/``release_field`` to ``HashKey``, rewriting the generated
  unique-index mutators to claim before the ``MULTI`` and re-affirm inside it,
  and wiring ``claim_unique_indexes!`` into ``prepare_for_save`` with rollback of
  partial claims. Added a tryouts suite covering the CAS primitives, legacy
  value normalization, the simulated save race, partial-claim rollback across two
  unique indexes, the in-transaction claim assertion, and ownership-checked
  release on ``destroy!``. Updated the edge-case tryout that previously asserted
  the buggy "last write wins" behavior.
