Fixed
-----

- ``Horreum#refresh!`` and ``Horreum#refresh`` now raise
  ``Familia::KeyNotFoundError`` when the record's key does not exist, as
  documented. They previously returned normally, kept unsaved in-memory field
  values and cleared dirty tracking, because the guard tested the Integer
  ``EXISTS`` reply for truthiness and ``0`` is truthy. Callers that refresh a
  record that may not be saved yet now need to rescue the error.
- ``HashKey#refresh!`` and ``HashKey#refresh`` now raise
  ``Familia::KeyNotFoundError`` for a missing key instead of
  ``Redis::CommandError: ERR wrong number of arguments for 'hmset' command``.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
