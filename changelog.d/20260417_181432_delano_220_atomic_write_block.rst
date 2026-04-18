Added
-----

- New ``Horreum#atomic_write(&block)`` method that wraps scalar field persistence
  and DataType collection mutations in a single Redis MULTI/EXEC transaction,
  providing true all-or-nothing atomicity for mixed updates. Unlike
  ``save_with_collections``, which sequences a save followed by a block (and
  cannot roll back scalars if a collection operation later fails),
  ``atomic_write`` routes every command -- HMSET for scalars, SADD/ZADD/etc.
  for collections, index and ``instances`` bookkeeping -- into one transaction.
  All participating DataTypes must share the parent Horreum's
  ``logical_database``; mismatches raise ``Familia::CrossDatabaseError``, in
  which case ``save_with_collections`` remains the appropriate fallback. (#220)

AI Assistance
-------------

- Design, implementation, testing, and review coordinated across multiple
  Claude Code (Opus 4.7) agents: an architect agent (``feature-dev:code-architect``)
  for the design, a ``backend-dev`` agent for the implementation, a
  ``qa-automation-engineer`` agent for the tryouts, and a
  ``feature-dev:code-reviewer`` agent that caught a silent-corruption gap in
  the cross-database guard where class-level related DataTypes were not being
  inspected. (#220)
