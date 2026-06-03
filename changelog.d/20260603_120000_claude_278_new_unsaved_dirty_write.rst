Changed
-------

- Mutating a collection (``list``/``set``/``zset``/``hashkey``) while its parent
  Horreum is a *new, unsaved* object -- one whose hash key does not exist in the
  database yet -- now **raises** ``Familia::Problem`` by default, independently of
  ``Familia.strict_write_order``. This is the most dangerous dirty-write case: the
  collection write would land in Redis while *none* of the parent's scalar data
  exists, orphaning the collection if the parent is never saved. The guard fires
  *before* the collection command runs, so no orphaned data is written. Previously
  this path only emitted a warning unless ``strict_write_order`` was enabled. Save
  the parent before mutating its collections (the recommended fix), or set
  ``Familia.raise_on_unsaved_parent_write = false`` to keep the old warn-only
  behaviour. A previously-saved parent with uncommitted scalar changes is
  unaffected -- it still only warns (or raises under ``strict_write_order``), and
  now with a message that no longer conflates the two cases. Issue #278

Added
-----

- ``Familia.raise_on_unsaved_parent_write`` (default ``true``) controls whether a
  collection write on a new, unsaved, dirty parent raises or merely warns. Set it
  to ``false`` via ``Familia.configure`` to downgrade the new-object case to a
  distinct, strongly-worded warning instead of an exception.
  ``Familia.strict_write_order`` continues to raise for every dirty write and
  overrides this setting. Issue #278

AI Assistance
-------------

- AI investigated how persistence state is (and is not) tracked on Horreum
  instances, implemented the new-object detection as a guarded ``exists?`` probe
  that short-circuits inside transactions/pipelines (so it never queues a stray
  EXISTS into an open MULTI/EXEC), falls back safely when the parent has no
  identifier yet, and traces that swallowed problem only when ``Familia.debug?``
  is set. Added the ``raise_on_unsaved_parent_write`` setting and tryout coverage
  for the full raise/warn matrix across new-vs-saved parents and both global
  settings. Two existing tryouts that mutated collections on unsaved dirty parents
  were updated to save the parent first, matching the guard's own guidance.
  Issue #278
