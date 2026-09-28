Changed
-------

- After ``Horreum#refresh!`` or ``Horreum#refresh``, a field that an ``init``
  hook set on an object built with ``new`` is ``nil`` when the stored hash has
  no value for it, as it is on an object returned by ``load``.

Fixed
-----

- ``Horreum#refresh!`` and ``Horreum#refresh`` set every persistent field
  that the stored hash does not contain to ``nil``, as ``load`` and
  ``find_by_id`` do. They kept the in-memory value, including an unsaved one,
  and then cleared dirty tracking. The identifier field keeps its value.
- ``Horreum#refresh!`` and ``Horreum#refresh`` no longer send ``HDEL`` to the
  ``objid_lookup`` or ``extid_lookup`` hash when the in-memory ``objid`` or
  ``extid`` differs from the stored one.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
