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

- ``max_length:`` is validated at definition time: it must be a positive
  Integer, and passing it to a type that does not implement capping
  (``HashKey``, ``UnsortedSet``, ``StringKey``, ``Counter``, …) raises
  ``ArgumentError`` instead of being silently ignored. #351

Fixed
-----

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
