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

- ``SortedSet#enforce_max_length!`` and ``ListKey#enforce_max_length!`` apply
  the cap to an already-oversized collection — the migration step after adding
  ``max_length:`` to live data, which otherwise stays over-cap until the next
  write. Both return the number of elements removed and raise
  ``Familia::Problem`` on an uncapped collection instead of silently doing
  nothing. Lists take ``keep: :tail`` (default, push-fed) or ``keep: :head``
  (unshift-fed) since the cap's per-end semantics belong to the write method,
  and run ``LLEN`` + ``LTRIM`` in one ``MULTI`` so the count is exact under
  concurrent writes. #351

- ``participates_in`` and ``class_participates_in`` accept ``max_length:``
  directly (``participates_in Owner, :activity, score: :created_at,
  max_length: 1000``), declaring the target collection capped with
  ``record_class:`` still threaded automatically. The value and collection
  type are validated at class-definition time, and a ``max_length:`` that
  conflicts with a pre-declared collection's cap (including an uncapped
  pre-declaration) raises ``ArgumentError`` rather than silently keeping the
  wrong cap. Pre-declaring the capped collection before ``participates_in``
  continues to work unchanged. A capped participation collection is a
  recent-N view, not authoritative membership: the trim does not touch each
  participant's ``participations`` reverse index, so ``member?``/``in_*?``
  stay accurate while ``current_participations`` can over-report. #351

- ``Familia::Features::Housekeeping::EnforceCollectionCaps`` ships the
  cap-enforcement sweep as a registerable chore class: it trims every capped
  collection on an instance via ``enforce_max_length!``, returning the removed
  count (truthy = modified) or ``nil`` on a clean pass so repeated runs are
  no-ops in ``run_chores!`` stats. Designed as a base class — override
  ``keep_for`` for unshift-fed lists, ``collection_names`` to scope the sweep.
  To support it, ``chore`` now accepts any ``#call``-able in place of a block
  (``chore :enforce_collection_caps, EnforceCollectionCaps``). #351

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
  of ``SortedSet`` and ``ListKey``, added ``enforce_max_length!`` and the
  ``participates_in`` / ``class_participates_in`` ``max_length:`` passthrough
  with conflict detection, shipped the ``Housekeeping::EnforceCollectionCaps``
  chore class (extending ``chore`` to accept callables), and wrote the
  documentation and this changelog entry.
