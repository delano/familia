Added
-----

- ``SortedSet`` and ``ListKey`` accept a ``max_length:`` option that caps the
  collection at write time (``sorted_set :audit_events, max_length: 10_000`` or
  ``Familia::SortedSet.new 'events', max_length: 100``). Every member-creating
  write trims in the same operation: sorted sets keep the N highest-scoring
  members (``ZREMRANGEBYRANK`` after ``ZADD``/``ZINCRBY`` — "newest N" only
  when scores are timestamps), lists keep the elements nearest the end written
  to (``push`` keeps the tail, ``unshift`` keeps the head). Standalone, each
  write+trim pair runs in its own ``MULTI`` so a crash cannot leave the
  collection over-cap; inside a caller transaction the outer ``MULTI`` covers
  the pair. ``unionstore``/``interstore``/``diffstore`` destinations,
  ``RESTORE``, and external writers are out of scope. #351

- ``DataType#max_length`` reads back the configured cap
  (``customer.audit_events.max_length #=> 10_000``), returning ``nil`` when the
  collection is uncapped. Defined on every DataType so a caller holding a
  generic collection can ask without first checking the type. Read-only: the
  cap is fixed at definition time. #351

- ``max_length:`` is validated at definition time: it must be a positive
  Integer, and passing it to a type that does not implement capping
  (``HashKey``, ``UnsortedSet``, ``StringKey``, ``Counter``, …) raises
  ``ArgumentError`` instead of being silently ignored. #351

Changed
-------

- ``SortedSet#increment`` (and its ``incr``/``incrby``/``decrement`` aliases)
  now runs the same ``warn_if_dirty!`` guard as ``add`` and ``update``. Writing
  through it from a dirty, never-saved parent warns — or raises, under the
  default ``raise_on_unsaved_parent_write`` — where it previously wrote
  silently. #351

Fixed
-----

- ``SortedSet#increment`` no longer raises ``NoMethodError`` when called inside
  a transaction or pipeline. ``ZINCRBY`` returns a ``Redis::Future`` there,
  which cannot be coerced with ``to_f`` until the block commits; the future is
  now passed through untouched, matching ``add``. #351

- The old ``:maxlength`` option spelling **was never honored** — it was
  silently stripped, so lists declared with it were never trimmed. It
  **remains ignored**: honoring it as an alias would begin mass-deleting
  previously untrimmed data on gem upgrade. It now emits a warning at
  definition time (``[familia] :maxlength is ignored; rename to
  max_length:``). Trimming requires an explicit rename to ``max_length:``.
  #351

AI Assistance
-------------

- Claude Code implemented the capped-write plumbing (shared
  ``execute_capped_write`` helper, ``supports_max_length?`` predicate,
  definition-time validation), wired trimming into all member-creating paths
  of ``SortedSet`` and ``ListKey``, and wrote the documentation and this
  changelog entry.
