Added
-----

- ``Familia.transform_reply(reply) { |r| ... }`` converts a concrete command
  reply and returns a ``Redis::Future`` untouched.
  ``Familia.transaction_or_pipeline?`` reports whether the current fiber is
  inside a Familia transaction or pipeline block.
  ``Familia.assert_replies_available!(operation)`` raises
  ``Familia::OperationModeError`` there.

Changed
-------

- Inside ``transaction``, ``atomic_write`` and ``pipelined`` blocks, DataType
  and Horreum methods that only convert a reply now return the command's
  ``Redis::Future`` instead of raising ``NoMethodError``. Its value is the
  reply as redis-rb returns it, without Familia's conversion (for example
  ``empty?`` resolves to the count). Affected: ``empty?`` on every
  collection, ``HashKey#values``, ``#hgetall``, ``#values_at``, ``#scan``,
  ``#randfield`` with ``withvalues: true``; ``ListKey#range``, ``#members``,
  ``#[]``, ``#member?``, ``#pop`` and ``#shift`` with a count;
  ``SortedSet#score``, ``#member?``, ``#rank``, ``#revrank``, ``#members``,
  ``#revmembers``, the range readers, ``#at``, ``#first``, ``#last``,
  ``#popmin``, ``#popmax``, ``#mscore``, ``#union``, ``#inter``, ``#diff``,
  ``#randmember``, ``#scan``; ``UnsortedSet#members``, ``#intersection``,
  ``#union``, ``#difference``, ``#scan``, ``#sample``; ``StringKey#size``,
  ``#empty?``, ``#to_s``, ``#to_i``; ``JsonStringKey#char_count``,
  ``#empty?``, ``#to_s``, ``#to_i``, ``#to_f``; ``Counter#value``, ``#to_i``,
  ``#reset``; ``Lock#locked?``, ``#held_by?``, ``#release``; ``expired?``;
  ``Horreum.any?``, ``.keys_count``, ``.keys_any?``, ``.in_instances?``,
  ``.multiget``, ``.storage_inspect``; ``Migration::Registry#applied_at``,
  ``#all_applied``, ``#metadata``; the generated participation methods
  ``score_in_<target>_<collection>`` and ``in_<target>_<collection>?`` on a
  sorted-set or list participation. Return values outside a block are
  unchanged.
- Methods that need a reply to continue now raise
  ``Familia::OperationModeError`` inside those blocks instead of
  ``NoMethodError`` or a wrong result: ``each`` and the raw iterators on
  every collection, ``HashKey#fetch``, ``#refresh!``, ``#refresh``,
  ``Counter#increment_if_less_than``, ``extend_expiration`` (returned
  ``false``), ``ttl_report``, ``Horreum#refresh!``, ``#refresh``, the
  finders and loaders (``find_by_dbkey``, ``find_by_identifier``,
  ``load_multi``, ``load_multi_by_keys``, ``all``, ``find_by_objid``,
  ``find_by_extid``), ``scan_count``, ``scan_any?``, class-level
  ``destroy!``, the index finders, rebuilds and ``guard_unique_*!`` methods,
  the participation readers, staged activation and unstaging, the
  ``audit_*``, ``health_check``, ``repair_*`` and ``scan_keys`` methods,
  ``run_chores!``, ``EnforceCollectionCaps``, ``Migration::Base.run`` and
  ``.check_only``, and ``Migration::Runner#run``, ``#run_one``,
  ``#rollback``, ``#status``, ``#pending``.
- ``Migration::Registry#pending``, ``#status``, ``#record_rollback``,
  ``#schema_changed?``, ``#schema_drift`` and ``#restore_backup`` raise
  ``Familia::OperationModeError`` when the registry's client is a
  transaction or pipeline connection. ``Migration::Registry#client`` no
  longer memoizes ``Familia.dbclient``, so a registry without its own client
  follows the current transaction or pipeline and no longer keeps a
  connection from a block that has completed.
- ``save``, ``save_if_not_exists!``, ``create!``, ``build`` and
  ``atomic_write`` raise ``Familia::OperationModeError`` inside a pipeline as
  well as a transaction. On a class with a unique index they raised a
  spurious ``Familia::RecordExistsError`` inside a pipeline.
- ``commit_fields``, ``save_fields``, ``multi_field_update`` and
  ``multi_field_fast_write`` raise ``Familia::OperationModeError`` inside any
  transaction or pipeline, before changing state. Previously only
  unique-indexed fields were refused; other fields raised ``NoMethodError``
  or left in-memory state out of step with the queued write.
- ``Horreum#destroy!`` raises ``Familia::OperationModeError`` inside a
  transaction or pipeline, before queueing anything, when the class has
  instance-scoped indexes. It previously raised ``NoMethodError`` after
  queueing any ``object_identifier`` and ``external_identifier`` lookup
  deletes. Other classes still queue their deletes into the caller's
  transaction.
- ``ListKey#insert``, ``#pushx``, ``#unshiftx`` and ``HashKey#hsetnx``
  queue their TTL refresh inside a transaction or pipeline instead of
  skipping it. ``SortedSet#popmin`` and ``#popmax`` queue theirs there too.
  The queued refresh runs whether or not the write takes effect, so
  ``hsetnx`` on an existing field and ``insert`` with a missing pivot reset
  the key's TTL there.

Fixed
-----

- ``HashKey#increment``, ``#decrement`` and ``#incrbyfloat`` raised
  ``NoMethodError`` inside ``transaction``, ``atomic_write`` and
  ``pipelined`` blocks, which aborted the whole block. They now return the
  command's ``Redis::Future``.
- ``HashKey#randfield(count, withvalues: true)`` returned
  ``[[[field, raw_value], nil]]`` when one pair came back and raised
  ``ArgumentError`` for more; it now returns ``[field, value]`` pairs.
- ``HashKey#hsetnx`` outside a block never refreshed the TTL. It now
  refreshes after setting a new field.
- ``Lock#release`` returned ``false`` inside a transaction even when the
  queued script released the lock.
- ``Migration::Registry#applied?`` returned ``true`` for every migration
  inside a transaction or pipeline. It now returns the ZSCORE
  ``Redis::Future``, which resolves to the score or ``nil`` after the block.
  The Future is truthy, so read its value after the block.

Documentation
-------------

- ``docs/reference/transaction_safety.md`` rule 4 describes how each method
  handles command replies inside transactions and pipelines.

AI Assistance
-------------

- The changes, regression tests and documentation were developed with AI
  assistance.
