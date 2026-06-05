Added
-----

- ``record_class:`` option for collection DataTypes (``list``/``set``/
  ``sorted_set``/``hashkey``). It is a loading-only hint that tells
  ``each_record`` which class to hydrate via ``load_multi``, WITHOUT changing how
  the collection serializes or deserializes reads. This complements
  ``class: + reference: true`` (used by ``instances``/``unique_index``), which
  additionally imposes raw-string read semantics — use ``record_class:`` when you
  want ``each_record`` but no read-behavior change. Issue #297

Fixed
-----

- ``each_record`` now works on ``participates_in`` and
  ``class_participates_in`` collections. Previously it raised
  ``Familia::Problem`` because participation collections were created without a
  record/reference class. ``ensure_collection_field`` (and the class-level
  builder) now declare the collection with ``record_class: <participant class>``,
  so iteration loads the participant records via ``load_multi``. Applies to all
  collection types (``:sorted_set``, ``:set``, ``:list``). Issue #297

- ``each`` / ``each_record`` no longer emit a per-member ``[deserialize] Raw
  fallback`` warning when iterating a ``record_class`` collection holding
  non-JSON identifiers (the common case — UUIDs, prefixed ids). Because the
  members are object identifiers by declaration, the raw value is expected and is
  now logged at debug level instead of warn. Non-``record_class`` collections are
  unaffected. Issue #297

Changed
-------

- ``participates_in`` / ``class_participates_in`` collection fields are now
  declared with ``record_class:``. **No data migration and no behavior change**:
  participation collections already stored raw identifiers, and ``record_class:``
  does not alter serialization — ``members``, ``to_a``, ``member?``, and
  ``score`` behave exactly as before (including JSON type-preservation for
  numeric-looking identifiers and the issue #212 "use objects, not raw strings"
  lookup rule). The only difference is that ``each_record`` now works. A
  collection pre-declared on the target class before ``participates_in`` runs is
  left as-is (the existing ``method_defined?`` guard wins); declare it with
  ``record_class:`` yourself if you want ``each_record`` on it. Issue #297

AI Assistance
-------------

- AI traced the bug from the participation builders through
  ``CollectionBase#each_record`` and confirmed it against a live database. After
  an initial reference-type fix, a fresh-agent review and follow-up analysis
  surfaced that ``reference: true`` carried a silent read-behavior change
  (numeric-string identifiers, ``member?`` semantics). AI redesigned the fix
  around a dedicated ``record_class:`` option that decouples each_record's
  record-class lookup from read deserialization, eliminating the read change;
  measured and fixed a resulting per-member deserialize-warning storm (scoping
  the quieting to ``record_class`` collections only); verified ``load_multi`` is
  identifier-type-tolerant so loading works regardless; kept ``instances`` and
  ``unique_index`` on ``class: + reference: true`` (their raw-string read
  semantics are intentional); made the unique-index rebuild fallback
  ``record_class``-aware; corrected a stale ``each_record`` flowchart in
  ``docs/guides/datatype-collections.md`` (``id = member.last`` for HashKey
  values, not ``member.first``); and added regression coverage in
  ``try/features/relationships/participation_each_record_try.rb`` (including a
  no-warning guard). Issue #297
