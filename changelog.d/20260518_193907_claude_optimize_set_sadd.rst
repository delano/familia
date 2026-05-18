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
  level, and confirmed zero regressions against the existing test suites.
