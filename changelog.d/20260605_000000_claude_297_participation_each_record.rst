Fixed
-----

- ``each_record`` now works on ``participates_in`` and
  ``class_participates_in`` collections. Previously it raised
  ``Familia::Problem`` ("each_record requires a reference DataType with a
  :class option that responds to load_multi") because participation collections
  were created without the ``class:`` option. ``ensure_collection_field`` (and
  the class-level builder) now declare the collection as a proper reference
  type (``class: <participant class>, reference: true``), matching the
  ``instances`` collection and the ``unique_index`` fix (#276), so iteration
  loads the participant records via ``load_multi``. Applies to all collection
  types (``:sorted_set``, ``:set``, ``:list``). Issue #297

Changed
-------

- ``participates_in`` / ``class_participates_in`` collection fields are now
  declared with ``class:`` and ``reference: true``. Unlike the ``unique_index``
  change in this release, **no data migration is required**: participation
  collections already stored raw identifiers (a Familia object serializes to
  its identifier), so the stored byte format is unchanged. Public reads
  (``members``, ``to_a``, ``member?``, ``score``) are unaffected for string
  identifiers. A collection pre-declared on the target class before
  ``participates_in`` runs is left as-is (the existing ``method_defined?``
  guard wins); declare it as a reference type yourself if you want
  ``each_record`` on it. Issue #297

AI Assistance
-------------

- AI traced the bug from the participation builders through
  ``CollectionBase#each_record``, confirmed it with a reproduction script
  against a live database (the raised error and ``opts[:class] == nil``),
  verified the reference-type fix produced correctly-typed records across
  sorted-set/set/list and both instance- and class-level participation,
  reasoned through the serialization paths to confirm no on-disk format change
  or regression to ``members``/``member?`` (including the pre-declared-field
  case exercised by ``serialization_consistency_try.rb``), corrected a stale
  ``each_record`` flowchart in ``docs/guides/datatype-collections.md`` (``id =
  member.last`` for HashKey values, not ``member.first``), updated the
  participation guide and v2.10.0 migration notes, and added regression
  coverage in
  ``try/features/relationships/participation_each_record_try.rb``. Issue #297
