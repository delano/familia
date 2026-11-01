Added
-----

- ``Familia.transform_reply(reply) { |r| ... }`` converts a concrete command
  reply and returns a ``Redis::Future`` untouched.
  ``Familia.transaction_or_pipeline?`` reports whether the current fiber is
  inside a Familia transaction or pipeline block.
  ``Familia.assert_replies_available!(operation, conn: nil)`` raises
  ``Familia::OperationModeError`` there. When ``conn`` is given it raises
  only when ``conn`` is a transaction or pipeline connection.

Changed
-------

- familia now requires ``redis`` 5.4 or later (``>= 5.4, < 6.0``, was
  ``>= 5.0``). ``Lock#release``, and inside a block ``HashKey#hsetnx``,
  ``JsonStringKey#setnx`` and ``JsonStringKey#value`` with a default, now
  pass a reply-coercion block to ``Redis#call``. redis-rb's changelog for
  5.4.0: "``Redis#call`` now accept a block, allowing to use ``Redis``
  instances where ``RedisClient`` is expected." Earlier versions ignore the
  block, so with them these methods would return, or their Futures resolve
  to, ``1`` or ``0`` instead of ``true`` or ``false``.
- Inside ``transaction``, ``atomic_write`` and ``pipelined`` blocks,
  DataType and Horreum methods that only convert a reply now return the
  command's ``Redis::Future`` instead of raising ``NoMethodError``. Its
  value is the reply as redis-rb returns it, without Familia's conversion
  (for example ``empty?`` resolves to the count). Affected: ``empty?`` on
  every collection, the generated related-field predicates (``user.tags?``,
  ``User.instances?``), ``HashKey#values``, ``#hgetall``, ``#values_at``,
  ``#scan``, ``#randfield`` with ``withvalues: true``; ``ListKey#range``,
  ``#members``, ``#[]`` (and ``#slice``) with a range or a start and
  length, ``#member?``, ``#pop`` and ``#shift`` with a count;
  ``SortedSet#score``, ``#member?``, ``#rank``, ``#revrank``, ``#members``,
  ``#revmembers``, the range readers, ``#at``, ``#first``, ``#last``,
  ``#popmin``, ``#popmax``, ``#mscore``, ``#union``, ``#inter``, ``#diff``,
  ``#randmember``, ``#scan``; ``UnsortedSet#members``, ``#intersection``,
  ``#union``, ``#difference``, ``#scan``, ``#sample``; ``StringKey#size``,
  ``#empty?``; ``JsonStringKey#char_count``, ``#empty?``; ``Counter#value``,
  ``#reset``; ``expired?``; ``Horreum.any?``, ``.keys_count``,
  ``.keys_any?``, ``.in_instances?``, ``.multiget``, ``.storage_inspect``;
  ``Migration::Registry#applied_at``, ``#all_applied``, ``#metadata``; the
  generated participation methods ``score_in_<target>_<collection>`` and
  ``in_<target>_<collection>?`` on a sorted-set or list participation.
  Return values outside a block are unchanged, except
  ``HashKey#randfield(count, withvalues: true)`` (see Fixed).
- Methods that need a reply to continue now raise
  ``Familia::OperationModeError`` inside those blocks instead of
  ``NoMethodError`` or a wrong result: ``each`` and the raw iterators on
  every collection, Ruby's conversion methods (``StringKey#to_s`` and
  ``#to_i``, which ``Counter`` and ``Lock`` inherit, ``JsonStringKey#to_s``,
  ``#to_i`` and ``#to_f``, ``to_a`` on ``ListKey``, ``SortedSet`` and
  ``UnsortedSet``, and ``as_json`` and ``to_json`` on every DataType; a
  scalar's ``as_json`` returned the GET Future and its ``to_json`` raised
  ``Familia::SerializerError``), ``HashKey#fetch``, ``#refresh!``,
  ``#refresh``, ``Counter#increment_if_less_than``, ``Lock#locked?``,
  ``Lock#empty?`` (and so the generated predicate of a ``lock`` field),
  ``Lock#held_by?`` (returned ``false``, even for the holder),
  ``extend_expiration`` (returned ``false``), ``ttl_report``,
  ``Horreum#refresh!``, ``#refresh``, the finders and loaders
  (``find_by_dbkey``, ``find_by_identifier``, ``load_multi``,
  ``load_multi_by_keys``, ``all``, ``find_by_objid``, ``find_by_extid``),
  ``scan_count``, ``scan_any?``, class-level ``destroy!``, the index
  finders, rebuilds and ``guard_unique_*!`` methods, the participation
  readers, ``current_indexings`` (reported every class-level index whose
  field was set), ``relationship_status``, ``validate_relationships!``, the
  ``audit_*``, ``health_check``, ``repair_*`` and ``scan_keys`` methods, the
  index format checks ``IndexDescriptor#stale_format?``,
  ``#format_current?``, ``Familia.stale_indexes`` and
  ``Familia.assert_indexes_current!`` (raised ``TypeError`` after queueing
  HRANDFIELD), ``AtomicOperations.atomic_swap``,
  ``.sweep_orphaned_temp_keys`` and ``.with_rebuild`` given a transaction
  or pipeline connection (``with_rebuild`` raised ``NoMethodError`` after
  queueing its lock), ``run_chores!``, ``EnforceCollectionCaps``,
  ``Migration::Base.run`` and ``.check_only``, and
  ``Migration::Runner#run``, ``#run_one``, ``#rollback``, ``#status``,
  ``#pending``.
- ``Migration::Registry#pending``, ``#status``, ``#record_rollback``,
  ``#schema_changed?``, ``#schema_drift`` and ``#restore_backup`` raise
  ``Familia::OperationModeError`` when the registry's client is a
  transaction or pipeline connection. ``Migration::Registry#client``
  without ``redis:`` returns the current transaction or pipeline connection
  inside a Familia block without keeping it, so it no longer keeps a
  connection from a block that has completed. Outside a block it still
  keeps the first ``Familia.dbclient`` it resolves, and ``#redis`` returns
  that kept connection (or the ``redis:`` client), never a transaction or
  pipeline connection. A registry built
  without ``redis:``, as ``Migration::Runner`` builds its default, and
  first used outside a block kept a plain connection for life: inside a
  later block its commands ran at once, outside the MULTI, and every
  registry method returned its usual value. Inside a block such a registry
  now returns the ``Redis::Future`` from ``applied?``, ``applied_at``,
  ``all_applied`` and ``metadata`` (``applied?`` resolves to the ZSCORE
  score or ``nil``, and the Future is truthy), queues ``record_applied``
  and returns its Future, and raises ``Familia::OperationModeError`` from
  the six methods above. A registry first used inside a block returned
  ``true`` from ``applied?`` for every migration and kept the block's
  connection, so a later ``record_applied`` returned a Future and wrote
  nothing. The block's connection is on the database the block was opened
  on, so inside a block opened by a model with another
  ``logical_database`` such a registry's commands go to that database. To
  keep a registry on its own connection, pass one:
  ``Familia::Migration::Registry.new(redis: Familia.create_dbclient)``.
- ``save``, ``save_if_not_exists!``, ``create!``, ``build``,
  ``atomic_write`` and ``Familia.atomic_write`` raise
  ``Familia::OperationModeError`` inside a pipeline as well as a
  transaction. Inside a pipeline they previously raised
  ``Familia::ConflictingContextError`` or a spurious
  ``Familia::RecordExistsError``.
- Inside a pipeline, the ``add_to_*`` and ``update_in_*`` methods of a
  ``unique_index`` raise ``Familia::OperationModeError`` before queueing
  anything, and the error names the method called. ``claim_unique_*!``
  names itself the same way inside a transaction or pipeline. Inside a
  pipeline they previously raised a spurious
  ``Familia::RecordExistsError`` (``add_to_*`` on an instance-scoped
  index), ``Familia::ConflictingContextError`` (``update_in_*`` with no
  field value) or an error naming ``HashKey#claim_field``, and ``add_to_*``
  with no field value returned ``nil``. Inside a transaction they behave as
  before.
- ``commit_fields``, ``save_fields``, ``multi_field_update`` and
  ``multi_field_fast_write`` raise ``Familia::OperationModeError`` inside any
  transaction or pipeline, before changing state. Inside a caller's
  transaction, ``multi_field_update`` and ``multi_field_fast_write``
  previously queued their write, which committed with the outer EXEC; call
  them before the block or use ``atomic_write``. ``commit_fields`` and
  ``save_fields`` raised ``NoMethodError`` there.
- The generated staged participation methods (``stage_<name>_instance``,
  ``stage_<name>``, ``activate_<name>_instance``, ``unstage_<name>_instance``,
  ``unstage_<name>``) and the add and remove methods of a ``through:``
  participation raise ``Familia::OperationModeError`` inside any transaction
  or pipeline before queueing anything, and the error names the generated
  method. Inside a caller's transaction, ``unstage_<name>_instance``
  previously queued its deletes, which committed with the outer EXEC, and
  returned ``true``; call it before or after the block. The others raised
  ``NoMethodError``, ``Familia::ConflictingContextError`` or an error naming
  an internal call, some after queueing part of their writes.
- ``Horreum#destroy!`` raises ``Familia::OperationModeError`` inside a
  transaction or pipeline, before queueing anything, when the class has
  instance-scoped indexes. It previously raised ``NoMethodError`` after
  queueing any ``object_identifier`` and ``external_identifier`` lookup
  deletes. Other classes still queue their deletes into the caller's
  transaction.
- ``ListKey#pushx`` and ``#unshiftx`` queue their TTL refresh inside a
  transaction or pipeline instead of skipping it. ``SortedSet#popmin`` and
  ``#popmax`` queue theirs there too, except with a count that pops
  nothing (``0`` or negative), as outside a block.
- Inside a transaction or pipeline, ``HashKey#hsetnx``, ``ListKey#insert``,
  ``JsonStringKey#setnx`` and ``JsonStringKey#value`` with a default queue
  their write and TTL refresh as one ``EVAL`` that refreshes only when the
  write takes effect, as outside a block. ``hsetnx`` and ``insert``
  previously skipped the refresh there; ``JsonStringKey#setnx`` and
  ``#value`` reset an existing key's TTL even when the key was already set.
  The returned Futures resolve to the same values as before.
  When the ``json_string`` has a default expiration (a positive
  ``default_expiration``, its own or inherited, and no
  ``no_expiration: true``), ``JsonStringKey#setnx`` and ``#value`` with a
  default now add one reply to ``MultiResult#results`` instead of two (the
  separate ``EXPIRE`` reply is gone), so later replies move up one index.
  Without a default expiration they added one reply before and still do.
  ``ListKey#pushx`` and ``#unshiftx`` on a list with a default expiration
  added one reply, the count, and now add two, the count then the
  ``EXPIRE`` reply, so the index of every later reply increases by one;
  without a default expiration they add one as before.
  ``SortedSet#popmin`` and ``#popmax``, which raised ``NoMethodError``
  there, add the ZPOPMIN or ZPOPMAX reply and, with a default expiration,
  the ``EXPIRE`` reply after it.
- Inside a transaction or pipeline, ``HashKey#hsetnx``, ``ListKey#insert``,
  ``JsonStringKey#setnx`` and ``JsonStringKey#value`` with a default send
  ``EVAL`` and need scripting permission (ACL ``@scripting`` or ``+eval``).
  Without it they raise ``Redis::PermissionError`` (``NOPERM``) and a
  transaction applies none of the block's commands. Outside a block they
  send the plain command as before.

Fixed
-----

- ``SortedSet#diff(withscores: true)`` raised ``ArgumentError: unknown
  keyword: :withscores``. It now returns ``[member, score]`` pairs.
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
  ``Redis::Future``, which resolves to ``true`` or ``false`` after the block,
  and ``MultiResult#results`` carries the same Boolean. The Future is truthy
  whatever the outcome, so read its value after the block. A queued release
  does not stop the block's other commands when the lock was lost before
  EXEC.
- ``JsonStringKey#empty?`` on a key declared with ``default:`` wrote the
  default to a missing key (SETNX) and refreshed the TTL. It now reads with
  GET only, inside and outside a block; its return value outside a block is
  unchanged.
- ``Familia::IndexedFieldFastWriteError`` raised by a ``field!`` fast
  writer inside a transaction or pipeline recommended ``multi_field_update``
  or ``save``, which raise ``Familia::OperationModeError`` there. Its
  message now says to write before or after the block, and the new
  ``#inside_block`` reader is ``true`` for that case.

Documentation
-------------

- ``docs/reference/transaction_safety.md`` rule 4 describes how each method
  handles command replies inside transactions and pipelines.
- ``docs/migrating/transaction-replies.md`` lists the calls inside a block
  that behaved differently before and need a code change: partial writes
  and unstaging that committed with an outer transaction,
  ``extend_expiration``, the ``Lock`` ownership checks and ``release``,
  ``current_indexings``, ``Migration::Registry`` without ``redis:``,
  ``as_json`` on a scalar DataType, the instance-scoped ``add_to_*`` with
  no field value inside a pipeline, the TTL refresh of ``HashKey#hsetnx``,
  ``ListKey#insert``, ``JsonStringKey#setnx`` and ``JsonStringKey#value``,
  and the TTL ``HashKey#hsetnx`` now sets outside a block.

AI Assistance
-------------

- The changes, regression tests and documentation were developed with AI
  assistance.
