Fixed
-----

- ``Horreum#refresh!``, ``Horreum#refresh``, ``HashKey#refresh!`` and
  ``HashKey#refresh`` raise ``Familia::OperationModeError`` inside a
  transaction, pipeline or ``atomic_write`` block, before sending any command.
  They raised ``NoMethodError`` on the ``Redis::Future`` returned by
  ``HGETALL``.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
