Added
-----

- ``SortedSet#update`` (aliased ``merge!``) for bulk member insertion. A sorted
  set is ``member => score`` -- the same pair shape as ``HashKey``'s
  ``field => value`` -- so it follows the established ``HashKey#update``/``merge!``
  convention (a single Hash argument) rather than the variadic splat used by the
  value-only ``UnsortedSet``/``ListKey``. Pass ``{member => score}`` to issue one
  ``ZADD`` instead of one round-trip per member. Validates the argument is a Hash
  and that every score is ``Numeric`` (a missing/``nil`` score raises a clear
  ``ArgumentError`` instead of a low-level client error -- unlike single-value
  ``#add``, the bulk path does not default a missing score to ``Familia.now``).
  Cascades expiration, and is a no-op returning ``0`` for empty input. The
  single-value ``SortedSet#add`` (and its array-as-single-member contract) is
  unchanged. PR #269

Changed
-------

- Bulk-write optimization for multi-value collection mutations. ``UnsortedSet#add``,
  ``ListKey#push``, and ``ListKey#unshift`` previously issued one Redis command per
  element (a loop of ``SADD``/``RPUSH``/``LPUSH`` calls), making large populations
  slow even when pipelined. They now serialize all values and issue a single bulk
  ``SADD``/``RPUSH``/``LPUSH`` command. Element ordering, ``nil`` compaction, nested
  array flattening, return values, dirty-write warnings, and expiration cascading
  are unchanged; empty calls remain no-ops. PR #269

AI Assistance
-------------

- AI investigated all collection ``DataType`` classes for the same per-element
  loop anti-pattern, identified the three affected methods, verified
  behavior-preservation (ordering, edge cases, chainability) at the Redis wire
  level, and confirmed zero regressions against the existing test suites. The
  ``SortedSet#update`` API shape was chosen by priority order: existing Familia
  conventions first (the ``HashKey#update``/``merge!`` precedent for keyed
  collections), then the upstream redis-rb bulk ``ZADD`` form, then Ruby
  ``Hash#merge!`` semantics as confirmation.
