Fixed
-----

- The ``WATCH``-based optimistic lock used by ``atomic_write(watch_keys:)``,
  ``save_if_not_exists!``, and therefore ``build``/``create!`` was **inert** in
  the default connection configuration: ``WATCH`` was sent on one connection
  while the ``MULTI/EXEC`` opened on another, so a concurrent modification of a
  watched key never aborted the write and could be silently overwritten. The
  ``WATCH`` and the ``MULTI`` are now driven through a single resolved
  connection, so the optimistic lock aborts on concurrent modification as
  documented. #296

AI Assistance
-------------

- Root-caused and fixed with Claude Code: identified the split-connection
  defect, designed the shared single-connection ``execute_watched_transaction``
  primitive (deliberately avoiding a fiber-pinning approach that would have
  silently degraded ``MULTI/EXEC`` to non-atomic individual commands), and
  replaced the previous *simulated* abort test with real concurrent-modification
  tests proven to fail on the old code and pass after the fix. #296
