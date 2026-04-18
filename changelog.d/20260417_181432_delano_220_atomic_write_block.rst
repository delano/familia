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

Fixed
-----

- ``atomic_write`` cross-database guard no longer raises a false positive when
  a Horreum inherits its ``logical_database`` and a related field explicitly
  sets ``logical_database: 0``; both sides are now resolved to concrete
  integers (falling through ``Familia.logical_database`` to ``0``) before
  comparison. (#220)

- ``atomic_write`` same-instance re-entrancy guard now uses a module-level
  ``Mutex`` to serialise the ``@atomic_write_owner`` check-then-set, closing
  a narrow race where two threads entering ``atomic_write`` on the same
  Horreum instance could both observe a nil owner and proceed into parallel
  MULTI blocks. (#220)

- ``atomic_write`` now clears the in-memory dirty flag only when the returned
  ``MultiResult.successful?`` is true, not merely when the result is non-nil.
  Previously a transaction whose individual commands returned exception
  objects (which MULTI swallows rather than raising) could leave the object
  marked clean despite the failed writes. (#220)

AI Assistance
-------------

- Design, implementation, testing, and review coordinated across multiple
  Claude Code (Opus 4.7) agents: an architect agent (``feature-dev:code-architect``)
  for the design, a ``backend-dev`` agent for the implementation, a
  ``qa-automation-engineer`` agent for the tryouts, and a
  ``feature-dev:code-reviewer`` agent that caught a silent-corruption gap in
  the cross-database guard where class-level related DataTypes were not being
  inspected. Follow-up review items (false-positive guard, re-entrancy race,
  MultiResult success semantics) were surfaced by the ``gemini-code-assist``
  review bot and verified by the ``qa-automation-engineer`` and
  ``feature-dev:code-reviewer`` agents. (#220)
