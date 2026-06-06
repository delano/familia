Added
-----

- ``Familia.atomic_write(*instances)`` persists multiple Horreum instances in a
  single ``MULTI/EXEC``, with an optional ``watch_keys:``/``pre_check:``
  create-only variant for race-safe "create A and B together" semantics. All
  participating instances (and their related fields) must resolve to one logical
  database, raising ``Familia::CrossDatabaseError`` otherwise; on Redis Cluster
  the keys must additionally share a hash slot (co-locate with hash tags). #296

AI Assistance
-------------

- Designed and implemented with Claude Code on top of the single-connection
  ``WATCH`` primitive: the all-roots same-database guard, the
  prepare-outside / persist-inside orchestration, and the test suite covering
  atomic two-model commit (invisible mid-transaction), rollback on error,
  cross-database rejection, the nesting guard, and a real create-only race. #296
