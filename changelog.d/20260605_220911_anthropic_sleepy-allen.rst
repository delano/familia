Added
-----

- Project-wide relationship introspection: ``Familia.index_descriptors``,
  ``Familia.unique_indexes``, ``Familia.multi_indexes``, and
  ``Familia.participation_descriptors`` aggregate index/participation metadata
  across every loaded ``Horreum`` subclass, returning ``Familia::IndexDescriptor``
  objects (``coordinate``, ``each_record``, ``rebuild!``, ``stale_format?``) that
  act without the caller knowing index method-naming or storage layout.

- Stale unique-index boot guard: ``Familia.stale_indexes`` and
  ``Familia.assert_indexes_current!`` detect class-level unique indexes still
  holding pre-2.10.0 JSON-encoded identifiers and fail fast (or warn) before an
  un-rebuilt index silently breaks a ``find_by_*`` lookup. Rebuild them with
  ``Familia.stale_indexes.each(&:rebuild!)``.

- ``Familia.legacy_json_encoded?`` exposes the legacy-format predicate shared by
  the read path (``strip_legacy_json_encoding``) and the introspection layer, so
  detection and stripping never disagree.

Documentation
-------------

- Documented the relationship introspection API — per-class
  (``indexing_relationships``/``participation_relationships``), project-wide, and
  per-instance — plus the stale-index boot guard, across the relationships guide
  and methods reference. Added a slimmed design note for the still-open optional
  persisted "clan manifest".

AI Assistance
-------------

- The introspection helpers, the stale-index boot guard, their tryouts, and the
  accompanying documentation were drafted with AI assistance.
