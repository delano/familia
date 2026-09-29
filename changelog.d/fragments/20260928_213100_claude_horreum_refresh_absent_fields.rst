Changed
-------

- ``Horreum#refresh!`` and ``Horreum#refresh`` set every persistent field
  that the stored hash does not contain to ``nil``, as ``load`` and
  ``find_by_id`` do. They kept the in-memory value and then cleared dirty
  tracking. This covers a value set in memory and never saved, a field
  another writer removed, and a default that an ``init`` hook set on an
  object built with ``new``. The identifier field keeps its value. See
  ``docs/migrating/refresh.md``.

Fixed
-----

- ``Horreum#refresh!`` and ``Horreum#refresh`` no longer send ``HDEL`` to the
  ``objid_lookup`` or ``extid_lookup`` hash when the in-memory ``objid`` or
  ``extid`` differs from the stored one.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
