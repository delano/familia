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

- Inside ``transaction``, ``atomic_write`` and ``pipelined`` blocks,
  DataType and Horreum methods that only convert a reply now return the
  command's ``Redis::Future`` instead of raising ``NoMethodError``. Its
  value is the reply as redis-rb returns it, without Familia's conversion
  (for example ``empty?`` resolves to the count). Affected: ``empty?`` on
  every collection, the generated related-field predicates (``user.tags?``,
  ``User.instances?``), ``HashKey#values``, ``#hgetall``, ``#values_at``,
  ``#scan``, ``#randfield`` with ``withvalues: true``; ``ListKey#range``,
  ``#members``, ``#[]``, ``#member?``, ``#pop`` and ``#shift`` with a count;
  ``SortedSet#score``, ``#member?``, ``#rank``, ``#revrank``, ``#members``,
  ``#revmembers``, the range readers, ``#at``, ``#first``, ``#last``,
  ``#popmin``, ``#popmax``, ``#mscore``, ``#union``, ``#inter``, ``#diff``,
  ``#randmember``, ``#scan``; ``UnsortedSet#members``, ``#intersection``,
  ``#union``, ``#difference``, ``#scan``, ``#sample``; ``StringKey#size``,
  ``#empty?``, ``#to_s``, ``#to_i``; ``JsonStringKey#char_count``,
  ``#empty?``, ``#to_s``, ``#to_i``, ``#to_f``; ``Counter#value``,
  ``#to_i``, ``#reset``; ``expired?``; ``Horreum.any?``, ``.keys_count``,
  ``.keys_any?``, ``.in_instances?``, ``.multiget``, ``.storage_inspect``;
  ``Migration::Registry#applied_at``, ``#all_applied``, ``#metadata``; the
  generated participation methods ``score_in_<target>_<collection>`` and
  ``in_<target>_<collection>?`` on a sorted-set or list participation.
  Return values outside a block are unchanged, except
  ``HashKey#randfield(count, withvalues: true)`` (see Fixed).
- Methods that need a reply to continue now raise
  ``Familia::OperationModeError`` inside those blocks instead of
  ``NoMethodError`` or a wrong result: ``each`` and the raw iterators on
  every collection, ``HashKey#fetch``, ``#refresh!``, ``#refresh``,
  ``Counter#increment_if_less_than``, ``Lock#locked?``, ``Lock#empty?`` (and
  so the generated predicate of a ``lock`` field), ``Lock#held_by?``
  (returned ``false``, even for the holder), ``extend_expiration`` (returned
  ``false``), ``ttl_report``, ``Horreum#refresh!``, ``#refresh``, the
  finders and loaders (``find_by_dbkey``, ``find_by_identifier``,
  ``load_multi``, ``load_multi_by_keys``, ``all``, ``find_by_objid``,
  ``find_by_extid``), ``scan_count``, ``scan_any?``, class-level
  ``destroy!``, the index finders, rebuilds and ``guard_unique_*!`` methods,
  the participation readers, ``current_indexings`` (reported every
  class-level index whose field was set), ``relationship_status``, staged
  activation and unstaging, the ``audit_*``, ``health_check``, ``repair_*``
  and ``scan_keys`` methods, ``run_chores!``, ``EnforceCollectionCaps``,
  ``Migration::Base.run`` and ``.check_only``, and
  ``Migration::Runner#run``, ``#run_one``, ``#rollback``, ``#status``,
  ``#pending``.
- ``Migration::Registry#pending``, ``#status``, ``#record_rollback``,
  ``#schema_changed?``, ``#schema_drift`` and ``#restore_backup`` raise
  ``Familia::OperationModeError`` when the registry's client is a
  transaction or pipeline connection. ``Migration::Registry#client`` no
  longer memoizes ``Familia.dbclient``. A registry without its own client
  resolves it once per method call, so it follows the current transaction
  or pipeline and no longer keeps a connection from a block that has
  completed. Without a connection provider, each registry method call opens
  one new connection; pass ``redis:`` to ``Registry.new`` to reuse one.
- ``save``, ``save_if_not_exists!``, ``create!``, ``build``,
  ``atomic_write`` and ``Familia.atomic_write`` raise
  ``Familia::OperationModeError`` inside a pipeline as well as a
  transaction. Inside a pipeline they previously raised
  ``Familia::ConflictingContextError`` or a spurious
  ``Familia::RecordExistsError``.
- ``commit_fields``, ``save_fields``, ``multi_field_update`` and
  ``multi_field_fast_write`` raise ``Familia::OperationModeError`` inside any
  transaction or pipeline, before changing state. Inside a caller's
  transaction, ``multi_field_update`` and ``multi_field_fast_write``
  previously queued their write, which committed with the outer EXEC; call
  them before the block or use ``atomic_write``. ``commit_fields`` and
  ``save_fields`` raised ``NoMethodError`` there.
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
- ``Lock#release`` returned ``false`` inside a transaction or pipeline even
  when the queued script released the lock. It now returns the EVAL
  ``Redis::Future``, which resolves to ``1`` or ``0`` after the block. The
  Future is truthy whatever the outcome, so read its value after the block.
- ``Migration::Registry#applied?`` returned ``true`` for every migration
  inside a transaction or pipeline. It now returns the ZSCORE
  ``Redis::Future``, which resolves to the score or ``nil`` after the block.
  The Future is truthy, so read its value after the block.

Documentation
-------------

- ``docs/reference/transaction_safety.md`` rule 4 describes how each method
  handles command replies inside transactions and pipelines.
- ``docs/migrating/transaction-replies.md`` lists the calls inside a block
  that behaved differently before and need a code change: partial writes
  that committed with an outer transaction, ``extend_expiration``, the
  ``Lock`` ownership checks and ``release``, ``current_indexings``,
  ``Migration::Registry#applied?`` and the TTL refresh of
  ``HashKey#hsetnx`` and ``ListKey#insert``.

AI Assistance
-------------

- The changes, regression tests and documentation were developed with AI
  assistance.
