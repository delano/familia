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
  longer identifier.
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
  ``multi_index`` whose scope record exists, unless the record the key names
  exists.

Added
-----

- ``Familia.escape_glob(str)`` escapes ``*``, ``?``, ``[``, ``]`` and ``\``
  for use in KEYS and SCAN MATCH patterns. It escapes bytes and keeps the
  input's encoding, so it accepts strings with invalid UTF-8 and binary data.
- ``Familia::IndexBucketConflictError`` (a ``Familia::PersistenceError``),
  whose ``conflicts`` maps each key to the type it holds and whose ``owners``
  maps each key of another record to that record's hash key.
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
  unchanged.
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

Fixed
-----

- With a glob character in the class prefix, delimiter or suffix, the
  methods above, the unique-index SCAN rebuild fallback and model migrations
  no longer include another class's keys or miss the class's own keys.
- A ``multi_index`` rebuild no longer deletes these keys of other records of
  the same class: the hash and fields of
  a record whose identifier equals a class-level index name, the set fields
  of a scope record whose identifier is ``<scope>:<index>``, and the buckets
  of a scope whose identifier starts with ``<scope>:<index>:``. Such a key
  belongs to the existing record with the longest identifier.
  ``audit_multi_indexes`` reads it for that record.
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
- ``audit_multi_indexes`` no longer reports a class-level bucket of the scope
  class whose field value contains ``:<index>:`` as an orphaned bucket of an
  instance-scoped index, unless the scope record the key names exists.

Documentation
-------------

- Documented ``multi_index`` rebuilds and ``Familia::IndexBucketConflictError``
  in the indexing guide and the index rebuilding reference.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
