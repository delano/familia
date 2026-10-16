Security
--------

- The generated ``rebuild_<index>`` of a ``multi_index`` put the scope
  instance's identifier (the class prefix, for a class-level index) into its
  SCAN pattern unescaped and deleted every match. Rebuilding the index of a
  scope whose identifier holds a glob character deleted other scopes' index
  sets: rebuilding ``c-*`` deleted those of ``c-1`` and ``c-2``. The literal
  part of the pattern is now escaped, and a matched key is deleted only if it
  starts with that literal prefix, holds a set and is not a set field or
  ``multi_index`` bucket of an existing record of the same class with a
  longer identifier. A record exists when its hash key holds a hash. A
  matched key with more than ``MAX_CANDIDATE_SPLITS`` candidate owner
  records stops the rebuild before it deletes anything.
- ``repair_participations!`` removed members from another class's collection
  of the same name when the target class prefix held a glob character.
  ``audit_participations`` now escapes the pattern and keeps only keys with
  the target's literal prefix and suffix.
- ``repair_related_fields!`` deleted a ``multi_index`` bucket whose field
  value equaled the name of a related field of the class, such as
  ``customer:role_index:notes`` for role ``notes`` and a ``notes`` field, or
  ``company:c-1:dept_index:tags`` for dept ``tags`` and a ``tags`` field of
  the scope class. ``repair_participations!`` removed every member of a
  bucket whose field value equaled a collection name. ``audit_related_fields``
  and ``audit_participations`` now skip a key that is a bucket of a
  class-level ``multi_index`` of the class, or of an instance-scoped
  ``multi_index`` whose scope record exists, unless the hash key of the record
  the key names holds a hash. The bucket of field value ``object`` is a set at
  such a hash key and does not count as that record.

Added
-----

- ``Familia.escape_glob(str)`` escapes ``*``, ``?``, ``[``, ``]`` and ``\``
  for use in KEYS and SCAN MATCH patterns. It escapes bytes and keeps the
  input's encoding, so it accepts strings with invalid UTF-8 and binary data.
- ``Familia::IndexBucketConflictError`` (a ``Familia::PersistenceError``),
  whose ``conflicts`` maps each key to the type it holds, or to
  ``:too_many_candidate_owners`` for a key whose owner was not checked, and
  whose ``owners`` maps each key of another record to that record's hash key.
- ``audit_multi_indexes`` results include ``foreign_owned_keys``: the sets
  under the bucket prefix that the rebuild leaves alone, each with ``key``,
  ``field_value``, ``owner_key`` and ``reason`` (``:other_record``, or
  ``:too_many_candidate_owners`` with a nil ``owner_key``), plus ``scope_id``
  for an instance-scoped index. An entry without an ``owner_key`` sets the
  status to ``:issues_found`` and makes ``AuditReport#healthy?`` false.
- ``Familia::Features::Relationships::Indexing::RecordKeyOwnership::MAX_CANDIDATE_SPLITS``
  (8), the most candidate owner records the rebuild and audits check for one
  key.
- ``Familia::Features::Relationships::Indexing::RecordKeyOwnership::MAX_CANDIDATE_BATCH_BYTES``
  (1 MiB), the most bytes of candidate owner identifiers the rebuild and
  audits check in one pipeline. An identifier longer than that is checked
  in a pipeline of its own.
- ``Familia::Horreum.dbkey_pattern(identifier_glob = '*', key_suffix = suffix)``
  returns a key pattern with the class prefix, delimiter and suffix escaped.
- ``Familia::Horreum::OBJECT_KEY_TYPE`` (``"hash"``), the Redis type of an
  object key.
- ``Familia::Migration::Model#scan_type``, the SCAN ``TYPE`` option of a model
  migration. It defaults to ``"hash"`` when ``@scan_pattern`` is left unset and
  to ``nil`` (every type) otherwise.

Changed
-------

- ``all``, ``scan_pattern``, ``keys_count``, ``scan_count``, ``keys_any?``,
  ``scan_any?`` and ``scan_keys`` escape the class prefix, delimiter and
  suffix. Identifier filters are still glob patterns. The ``all`` and
  ``scan_pattern`` arguments are now literal suffixes.
- ``find_keys`` escapes the class prefix and delimiter. Its suffix argument
  is still a glob pattern.
- The generated ``rebuild_<index>`` of a ``multi_index`` checks every bucket
  key it will write before it deletes anything. If one holds a type other
  than set, or is a set field or ``multi_index`` bucket of an existing record
  of the same class with a longer identifier, it raises
  ``Familia::IndexBucketConflictError`` and leaves the index and that key
  unchanged. It raises the same way, before deleting anything, when a key it
  would write or delete has more than ``MAX_CANDIDATE_SPLITS`` candidate owner
  records.
- The ``rebuild_<index>`` of a ``multi_index`` reports a bucket key to its
  progress block in the ``:clearing`` phase, and counts it, only when its
  ``DEL`` removed the key.
- ``repair_multi_indexes!`` records a rebuild that raises
  ``Familia::IndexBucketConflictError`` in ``:skipped`` with
  ``reason: :bucket_conflict``, ``conflicts``, ``owners`` and, for an
  instance-scoped index, ``scope_id``, and goes on with the next scope or
  index. ``repair_all!`` returns status ``:partial_failure`` for such an entry.
- The ``multi_index`` rebuild and ``audit_multi_indexes`` pass the ``TYPE``
  option to SCAN when they look for bucket sets.
- ``audit_related_fields`` and ``audit_participations`` pass the ``TYPE``
  option to SCAN for the type the field or collection stores, so keys of
  another type are not reported or repaired.
- ``all``, ``keys_count``, ``scan_count``, ``keys_any?``, ``scan_any?``,
  ``scan_keys``, ``audit_instances``, ``rebuild_instances``, the unique-index
  SCAN rebuild fallback and model migrations with the default
  ``@scan_pattern`` use only matching keys that hold a hash.
- ``Familia::Migration::Model`` defaults ``@scan_pattern`` to the model
  class's ``scan_pattern``, which follows ``Familia.delim`` and the class
  suffix instead of a hardcoded ``:`` and ``object``.
- The instance-scoped ``add_to_*`` and ``update_in_*`` of a ``multi_index``
  no longer add an object whose field value is blank (``nil``, empty or
  whitespace only) to ``<scope key>:<index>``, the key ``<index>_for`` names
  for a blank value, as the class-level methods already did. They still
  record the membership, so ``save`` indexes the object once its value is no
  longer blank. The instance-scoped ``find_all_by_*`` and ``sample_from_*``
  return ``[]`` for a blank value, as the class-level ``sample_from_*``
  already did. Keys and related-field members these methods wrote for blank
  values before stay in place after upgrading. The methods of that scope do
  not read the key as data, because ``<scope key>:<index>`` can also be a
  related field of the scope class with the index's name. When the scope
  identifier contains the delimiter, the key can also be a bucket of an index
  of a shorter scope. When the scope identifier is the name of a class-level
  index of the scope class, or starts with that name and the delimiter, the
  key can also be a class-level bucket of that index. The audit of that
  other index reads such a key and its rebuild deletes or rewrites it, unless
  the scope class declares a set field named ``<index>`` and the scope record
  with that identifier exists. Familia does not tell such a key apart from a live bucket or
  a related field; see the indexing guide's "Blank field values" section.

Fixed
-----

- With a glob character in the class prefix, delimiter or suffix, the
  methods above, the unique-index SCAN rebuild fallback and model migrations
  no longer include another class's keys or miss the class's own keys.
- A ``multi_index`` rebuild no longer deletes these keys of other records of
  the same class: the hash and fields of a record whose identifier equals a
  class-level index name, the set fields of a scope record whose identifier is
  ``<scope>:<index>``, and the buckets of a scope whose identifier starts with
  ``<scope>:<index>:``. Such a key belongs to the existing record with the
  longest identifier. ``audit_multi_indexes`` reads it for that record. A key
  that ends in an instance-scoped index name, such as
  ``company:c-1:dept_index:x:dept_index``, is a key of record
  ``c-1:dept_index:x`` only when the scope class declares a set field of that
  name; otherwise it is the bucket of ``x:dept_index`` in ``c-1``.
- ``audit_multi_indexes``, ``repair_multi_indexes!``, ``repair_all!`` and
  ``health_check`` no longer raise ``Redis::WrongTypeError`` when a key under
  a multi-index bucket prefix is not a set, such as the hash of a record
  whose identifier equals a class-level index name.
- A ``multi_index`` bucket whose field value equals the class suffix, such as
  ``customer:role_index:object``, is no longer taken for an object:
  ``audit_instances`` no longer reports it as missing, ``scan_count`` and
  ``keys_count`` no longer count it, and ``all``, ``health_check``,
  ``repair_instances!`` and ``rebuild_instances`` no longer raise
  ``Redis::WrongTypeError``.
- ``audit_participations`` no longer raises ``Redis::WrongTypeError`` on a
  set bucket named like a sorted set or list collection.
- ``extract_identifier_from_key`` compares and slices the key as bytes and
  returns the identifier in the key's encoding. ``audit_instances`` and
  ``audit_related_fields`` of a class whose prefix holds non-ASCII characters
  no longer raise ``Encoding::CompatibilityError`` for a record whose
  identifier is not valid UTF-8. Neither does ``health_check`` of such a
  class when it declares no ``unique_index`` or ``multi_index``.
- ``audit_multi_indexes`` and ``health_check`` of a class with an
  instance-scoped ``multi_index`` no longer raise
  ``Encoding::CompatibilityError`` when the scope class prefix holds
  non-ASCII characters and a scope identifier is not valid UTF-8.
- With a blank field value, a ``multi_index`` no longer reads or changes a
  related field whose name equals the index name, such as a
  ``class_set :roles`` beside ``multi_index :role, :roles`` or a ``set :tags``
  of the scope class beside ``multi_index :tag, :tags, within: Company``. The
  instance-scoped ``remove_from_*`` and ``update_in_*`` and the class-level
  ``update_in_class_*`` removed the object from it, the class-level
  ``find_all_by_*`` returned its members, and ``indexed_in?`` and
  ``current_indexings`` read it. ``IndexDescriptor#each_record`` raises
  ``ArgumentError`` for a blank ``value:`` of a ``multi_index``, as it does
  for ``nil``; it iterated the related field's members.
- ``audit_multi_indexes`` no longer reports a class-level bucket of the scope
  class whose field value contains ``:<index>:`` as an orphaned bucket of an
  instance-scoped index, unless the hash key of the scope record the key
  names holds a hash.

Documentation
-------------

- Documented ``multi_index`` rebuilds and ``Familia::IndexBucketConflictError``
  in the indexing guide and the index rebuilding reference.
- Added ``docs/migrating/key-patterns-and-index-rebuilds.md``, the migration
  guide for the changes above.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
