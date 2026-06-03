Changed
-------

- Dirty-write warnings now treat a *new, unsaved* parent as a distinct case.
  When a collection (``list``/``set``/``zset``/``hashkey``) is mutated while its
  parent Horreum has uncommitted scalar changes, ``warn_if_dirty!`` distinguishes
  a parent that has never been persisted (no hash key exists in the database yet)
  from one that was saved before and merely has pending changes. The former is
  the more dangerous case -- the collection write lands in Redis while *none* of
  the parent's scalar data exists, orphaning the collection if the process never
  saves -- so it now emits a distinct, stronger message ("... is a new, unsaved
  object (no hash key exists yet) ...") and, under ``Familia.strict_write_order``,
  raises with that same message. Previously-saved-but-dirty parents keep the
  original wording and behaviour. Issue #278

AI Assistance
-------------

- AI investigated how persistence state is (and is not) tracked on Horreum
  instances, implemented the new-object detection as a guarded ``exists?`` probe
  that short-circuits inside transactions/pipelines (so it never queues a stray
  EXISTS into an open MULTI/EXEC) and falls back safely when the parent has no
  identifier yet, and added tryout coverage for the new-vs-saved distinction in
  both warning and strict modes. Issue #278
