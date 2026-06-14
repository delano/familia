Fixed
-----

- ``SortedSet#members(n)`` / ``#revmembers(n)`` returned one fewer element than
  requested. Both ``members`` and ``membersraw`` decremented the count, so a
  positive ``n`` resolved to ``n-1`` elements (``ListKey#members`` was already
  correct). The count math now happens once.

- Generated participation permission queries
  (``<collection>_with_permission``) were dead code: they called
  ``SortedSet#zrangebyscore`` (which does not exist) with a fallback that also
  raised, and a score-range query cannot filter by permission anyway (permission
  bits live in the fractional part of the score and are not a contiguous range).
  The query now fetches members with scores and filters each via
  ``ScoreEncoding.permission?``.

- Class-level ``Model.destroy!(id)`` left unique-index entries orphaned (the
  instance ``#destroy!`` already cleaned them). A stale ``find_by_<field>`` could
  resolve a deleted record, and the freed value could not be reused because the
  unique guard still saw the orphan. ``destroy!`` now loads the record before the
  transaction and removes its class-level index entries atomically.

- Changing a ``unique_index`` field value and saving left the old value's index
  entry orphaned. Auto-indexing on save is now old-value-aware (via dirty
  tracking) for unique indexes: the previous value's mapping is removed in the
  same save transaction. ``multi_index`` keeps its existing add-only semantics.

AI Assistance
-------------

- These four fixes, their failing-first tryouts, and this changelog were drafted
  with AI assistance during a code review of the relationships and data-type
  subsystems.
