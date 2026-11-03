Changed
-------

- ``HashKey#refresh!`` returns the fields it read as a ``Hash``, as
  ``HashKey#hgetall`` returns them, instead of the ``HMSET`` reply ``"OK"``.
- ``HashKey#refresh!`` and ``HashKey#refresh`` no longer reset the key's
  expiration. Call ``update_expiration`` to extend it. See
  ``docs/migrating/refresh.md``.
- ``HashKey#refresh!`` and ``HashKey#refresh`` no longer run the dirty-write
  check against the parent, so they no longer warn or raise
  ``Familia::Problem`` when the parent has unsaved fields.

Fixed
-----

- ``HashKey#refresh!`` and ``HashKey#refresh`` no longer write to the hash.
  They sent ``HMSET`` with the values ``HGETALL`` had just returned; they now
  send only ``HGETALL``.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
