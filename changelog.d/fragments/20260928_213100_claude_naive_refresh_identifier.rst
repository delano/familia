Fixed
-----

- ``Horreum#naive_refresh`` no longer raises ``Familia::NoIdentifier`` on an
  object whose identifier is not set yet.
- ``Horreum#naive_refresh`` no longer sends ``HDEL`` to ``objid_lookup`` on an
  object with no ``objid`` yet whose Proc identifier reads ``objid``.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
