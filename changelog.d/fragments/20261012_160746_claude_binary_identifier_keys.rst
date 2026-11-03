Added
-----

- Added ``Familia.normalize_key_encoding(str)``, which returns ``str`` as
  UTF-8 when its bytes are valid UTF-8 and as BINARY otherwise, the encoding
  redis-client gives a key or member it reads. The bytes are unchanged.
  PR #453

Changed
-------

- ``Familia.join``, and so ``Familia.dbkey``, ``Horreum.dbkey``,
  ``Horreum#dbkey`` and the ``dbkey`` of a DataType with a parent, returns
  its result in the encoding ``Familia.normalize_key_encoding`` gives it. Key
  bytes are unchanged; the encoding changes for an identifier that is UTF-8
  with invalid bytes (now BINARY), BINARY with valid UTF-8 bytes (now UTF-8),
  or in another encoding with non-ASCII bytes, such as ISO-8859-1 (now BINARY
  or UTF-8 by its bytes), and for an ASCII-only result of US-ASCII, Symbol or
  Integer parts (now UTF-8). A DataType's ``dbkey:`` option, a standalone
  DataType's key and the patterns of ``dbkey_pattern``, ``scan_pattern`` and
  ``find_keys`` keep the encoding they are given, and ``dbkey_pattern`` still
  raises ``Encoding::CompatibilityError`` for a BINARY or ISO-8859-1
  identifier glob with non-ASCII bytes under a non-ASCII prefix. See
  ``docs/migrating/dbkey-encoding.md``. PR #453
- ``DatabaseLogger.command_string``, the text of captured commands and of
  unstructured log lines, always returns UTF-8 or ASCII-only text. When the
  joined command is not valid UTF-8, or its arguments' encodings are
  incompatible, each argument is read as UTF-8 with every invalid byte
  written as ``\xNN``, so a BINARY member ``"bad\xFF"`` reads ``bad\xFF``
  with a literal backslash and a BINARY argument with valid UTF-8 bytes
  reads as that text. Structured log lines are unchanged. PR #453
- Familia log lines that name a key next to other text, the structured
  context of ``Familia.debug``, ``Familia.info`` and ``Familia.error``,
  ``Familia.trace`` output, and the ``HashKey`` store,
  ``Familia::IdentifierMismatchError`` and dirty-write messages show a key or
  value whose bytes are not valid UTF-8 with every invalid byte written as
  ``\xNN``. The legacy JSON-encoded identifier warning writes ``->`` instead
  of ``→``. PR #453
- The ``participations`` reverse-index entry for a target whose identifier is
  in an encoding other than UTF-8 or BINARY and has non-ASCII bytes, such as
  ISO-8859-1 ``"caf\xE9"``, holds the collection key's bytes. 2.13 and 2.14
  stored the key transcoded to UTF-8, which is not the collection's key.
  ``remove_from_<target>_<collection>`` does not remove an entry written by
  2.13 or 2.14, and adding the membership again leaves both. When such an
  identifier's bytes are not valid UTF-8, ``participating_ids_for_target``,
  ``current_participations``, and ``participating_in_target?`` given
  collection names raise ``ArgumentError`` for the target, as they already
  did for a BINARY target identifier that is not valid UTF-8. When they are
  valid UTF-8, ``participating_ids_for_target`` returns them as a UTF-8
  identifier, which finds the target; 2.14 returned one that found no
  record. PR #453

Fixed
-----

- ``Familia.join`` no longer raises ``Encoding::CompatibilityError`` when its
  parts carry non-ASCII bytes in incompatible encodings, such as a non-ASCII
  class ``prefix`` with a BINARY identifier. The parts are joined as bytes, so
  ``save``, ``exists?``, ``load`` and ``rebuild_instances`` work for such a
  record. PR #453
- ``save`` of a loaded record whose identifier is not valid UTF-8 no longer
  raises ``Familia::RecordExistsError`` from ``guard_unique_<index>!`` or
  ``guard_unique_<scope>_<index>!`` against the record's own index entry. The
  guards compare identifiers by their bytes. PR #453
- ``audit_participations``, and so ``health_check``, of a class whose prefix
  holds non-ASCII characters no longer raise ``Encoding::CompatibilityError``
  when an identifier that is not valid UTF-8 is a member of a participation
  collection. PR #453
- ``audit_multi_indexes``, ``repair_multi_indexes!`` and ``health_check`` of
  a class with an instance-scoped ``multi_index`` and ``participates_in`` of
  the scope class no longer raise ``Encoding::CompatibilityError`` when a
  scope identifier labelled UTF-8 or BINARY is not valid UTF-8 and the scope
  class prefix or the field value holds non-ASCII characters. The audit
  matches such a bucket to its scope and records, including the bucket of a
  scope whose identifier contains the delimiter and the index name. For a
  scope identifier in another encoding with non-ASCII bytes, such as
  ISO-8859-1 ``"caf\xE9"``, the audit still reports the scope's buckets as
  ``:field_value_unheld`` orphans and ``repair_multi_indexes!`` rebuilds them
  on every run. PR #453
- An instance-scoped ``multi_index`` with a non-ASCII field value no longer
  raises ``Encoding::CompatibilityError`` from ``add_to_<scope>_<index>``,
  ``update_in_<scope>_<index>`` or ``remove_from_<scope>_<index>`` given a
  scope whose identifier is not labelled UTF-8 and holds non-ASCII bytes
  (BINARY, such as ``'zoé'.b`` or ``"bin\xFE".b``, or ISO-8859-1), or from
  ``save`` or ``destroy!`` of a record indexed in a scope whose identifier is
  not valid UTF-8. ``destroy!`` removes the record's index entries. PR #453
- Reading a collection with non-ASCII members (``members``, ``each``,
  ``revrange``), ``rebuild_<index>``, ``commit_fields`` and
  ``HashKey#refresh!`` no longer raise ``Encoding::CompatibilityError`` for a
  record or scope given a BINARY identifier that is not valid UTF-8. With
  debug on, the same holds for ``find_by_id`` and collection writes. PR #453
- A record whose indexed field value is not valid UTF-8, such as a value
  given as BINARY ``"r\xFEle".b``, which loads back as UTF-8 with the same
  bytes, no longer makes ``save`` and ``destroy!`` of the loaded record, or
  ``audit_multi_indexes``, ``audit_unique_indexes``, ``health_check`` and
  ``repair_all!`` of its class, raise ``ArgumentError`` or
  ``Encoding::CompatibilityError``. The audits no longer report its index
  entries as stale, missing and orphaned. PR #453
- ``DatabaseLogger`` no longer raises ``Encoding::CompatibilityError`` after
  a command whose arguments are in incompatible encodings, or, with
  unstructured logging, after a command with a non-ASCII BINARY argument.
  The command had run, but the caller received the error. PR #453

Documentation
-------------

- Added ``docs/migrating/dbkey-encoding.md``, which lists the encoding of a
  key before and after, the log text changes, the participations
  reverse-index entries and audits for ISO-8859-1 identifiers, what to
  change, and what 2.14 cannot read or delete after a rollback. PR #453

AI Assistance
-------------

- The fix, regression tests and migration guide were developed with AI
  assistance.
