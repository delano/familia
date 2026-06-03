Fixed
-----

- ``each_record`` now works on ``unique_index`` hashkeys. Previously it raised
  ``Familia::Problem`` ("each_record requires a reference DataType with a
  :class option that responds to load_multi") because ``unique_index`` created
  its backing hashkey without the ``class:`` option. The index hashkey is now
  declared as a proper reference type (``class: indexed_class,
  reference: true``), matching the ``instances`` collection, so iteration loads
  the indexed records via ``load_multi``. Applies to both class-level
  (``unique_index :email, :email_lookup``) and instance-scoped
  (``unique_index :badge, :badge_index, within: Company``) indexes. Issue #276

- ``each_record`` extracts the stored identifier (the hash *value*) from a
  HashKey instead of the indexed field (the hash *key*). A ``unique_index``
  maps ``field_value => identifier``, so the value is the record identifier
  passed to ``load_multi``. List/Set/SortedSet behaviour is unchanged (their
  members are already identifiers). Issue #276

Changed
-------

- ``unique_index`` hashkeys now store object identifiers as raw strings
  (reference semantics) rather than JSON-encoded strings. A value previously
  stored as ``"\"u1\""`` is now stored as ``"u1"``. Reads through
  ``find_by_*``/``hgetall``/``get`` are unaffected (they round-trip to the same
  identifier), but the on-disk format differs. After upgrading, rebuild
  existing unique indexes to convert legacy entries, e.g.
  ``User.rebuild_email_lookup`` (class-level) or
  ``company.rebuild_badge_index`` (instance-scoped). This also removes a latent
  inconsistency where the auto-index mutation path wrote JSON-encoded values
  while ``rebuild_*`` wrote raw identifiers. Issue #276

AI Assistance
-------------

- AI diagnosed the root cause, confirmed it with reproduction scripts against a
  live database (showing the raised error, the JSON-vs-raw storage format, and
  that a naive ``class:``-only fix would break ``find_by_*`` and silently yield
  zero records from ``each_record``), implemented the reference-type fix across
  the class-level and instance-scoped generators, corrected the ``each_record``
  field-vs-value extraction, updated audit/repair test fixtures that pinned the
  old storage format, and added focused regression coverage in
  ``try/features/relationships/unique_index_each_record_try.rb``. Issue #276
