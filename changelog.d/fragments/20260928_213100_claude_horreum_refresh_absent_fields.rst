Added
-----

- ``Familia::IdentifierMismatchError`` (a ``Familia::HorreumError``), with
  ``#key`` and ``#resolved_key``.

Changed
-------

- ``Horreum#refresh!`` and ``Horreum#refresh`` set every persistent field
  that the stored hash does not contain to ``nil``, as ``load`` and
  ``find_by_id`` do. They kept the in-memory value and then cleared dirty
  tracking. This covers a value set in memory and never saved, a field
  another writer removed, and a default that an ``init`` hook set on an
  object built with ``new``. A Symbol or String identifier field that is
  not stored keeps its value. See ``docs/migrating/refresh.md``.
- ``Horreum#refresh!`` and ``Horreum#refresh`` raise
  ``Familia::IdentifierMismatchError`` and leave the object unchanged when
  the stored values give no identifier or one that names a different key,
  for example a stored identifier field that differs from the key, or a
  missing field that a Proc or method identifier reads. They assigned those values,
  so a later ``save`` wrote to another record or created a new one. See
  ``docs/migrating/refresh.md``.

Fixed
-----

- ``Horreum#refresh!`` and ``Horreum#refresh`` no longer send ``HDEL`` to the
  ``objid_lookup`` or ``extid_lookup`` hash when the in-memory ``objid`` or
  ``extid`` differs from the stored one.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
