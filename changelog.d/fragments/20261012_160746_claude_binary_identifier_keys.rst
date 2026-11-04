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
- The deserialization, ``find_by_id``, ``commit_fields``, ``refresh!``,
  ``update_expiration``, ``serialize_value`` and ``HashKey`` write log lines,
  the warning for an indexed field value longer than 256 characters, the
  structured context of ``Familia.debug``, ``Familia.info`` and
  ``Familia.error``, ``Familia.trace`` output, and the messages of the
  ``TypeError`` a ``HashKey`` store raises, ``Familia::IdentifierMismatchError``,
  ``WatchAbortError`` and the dirty-write warning and error show a key or
  value whose bytes are not valid UTF-8 with every invalid byte written as
  ``\xNN``. Other log lines that name a key, such as those of the atomic
  index rebuild and of ``repair_participations!``, write its bytes as they
  are. The legacy JSON-encoded identifier warning writes ``->`` instead of
  ``→``. PR #453
- The ``participations`` reverse-index entry for a target whose identifier is
  in an encoding other than UTF-8 or BINARY and has non-ASCII bytes, such as
  ISO-8859-1 ``"caf\xE9"``, holds the collection key's bytes. 2.13 and 2.14
  stored the key transcoded to UTF-8, which is not the collection's key.
  ``remove_from_<target>_<collection>`` does not remove an entry written by
  2.13 or 2.14, and adding the membership again leaves both.
  ``participating_ids_for_target`` returns the identifier's bytes, as UTF-8
  when they are valid UTF-8 and as BINARY otherwise (``"caf\xE9".b``),
  which finds the target; 2.14 returned one that found no record.
  ``current_participations`` and ``relationship_status`` leave the
  membership out and return the participant's other memberships, as 2.14
  did. PR #453

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
  guards compare identifiers by their bytes. Nor do they raise it against
  the own entry of a record with an Integer identifier when the application
  declared the index hashkey itself, before ``unique_index``; for another
  record's entry in such an index they raise ``Familia::RecordExistsError``.
  As 2.14 did for ``'q'`` against ``'"q"'``, they read a stored owner
  wrapped in one pair of double quotes as the identifier inside, so a
  record given ``"\xFF"`` now passes them and takes the entry of a record
  whose identifier is ``"\"\xFF\""``. Do not use identifiers that start
  and end with a double quote with unique indexes. PR #453
- ``audit_participations``, and so ``health_check``, of a class whose prefix
  holds non-ASCII characters no longer raise ``Encoding::CompatibilityError``
  when an identifier that is not valid UTF-8 is a member of a participation
  collection. PR #453
- ``current_participations``, ``relationship_status``,
  ``participating_ids_for_target``, ``participating_in_target?`` given
  collection names, and the generated ``<target>_ids``,
  ``<target>_instances`` and ``<target>_count`` no longer raise
  ``ArgumentError`` (invalid byte sequence in UTF-8) for a participant
  whose ``participations`` set holds an entry for a target identifier that
  is not valid UTF-8, given as BINARY (``"bin\xFE".b``) or as UTF-8. They
  read each entry by its bytes. ``current_participations`` returns the
  participant's other memberships and that membership, with ``target_id``
  the identifier's bytes as BINARY. PR #453
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
  ``revrange``), ``rebuild_<index>``, ``commit_fields``, ``HashKey#refresh!``,
  ``Horreum#refresh!`` of a record with a legacy plain-string field value,
  and reading a legacy JSON-encoded entry of a scope's ``unique_index`` or
  ``multi_index`` (``[]``, ``get``, ``members``, ``find_by_<field>``,
  ``find_all_by_<field>``) no longer raise ``Encoding::CompatibilityError``
  for a record or scope given a BINARY identifier that is not valid UTF-8.
  Nor does adding such a record of a class whose name holds non-ASCII text
  to a collection. With debug on, the same holds for ``find_by_id`` and
  collection writes. PR #453
- ``atomic_write`` given ``watch_keys:`` that include a BINARY key with
  non-ASCII bytes, such as the key of a record given ``"bin\xFE".b``, and a
  non-ASCII UTF-8 key retries a WATCH conflict and raises
  ``WatchAbortError`` when the retries run out, instead of raising
  ``Encoding::CompatibilityError`` on the first conflict. PR #453
- A record whose indexed field value is not valid UTF-8, such as a value
  given as BINARY ``"r\xFEle".b``, which loads back as UTF-8 with the same
  bytes, no longer makes ``save`` and ``destroy!`` of the loaded record with
  a ``multi_index`` on that field, or ``audit_multi_indexes``,
  ``audit_unique_indexes``, ``health_check`` and ``repair_all!`` of its
  class, raise ``Encoding::CompatibilityError``. ``save`` and
  ``find_all_by_<field>`` no longer raise it for a ``multi_index`` value
  longer than 256 characters given as BINARY with non-ASCII bytes under a
  class whose name holds non-ASCII text. PR #453
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
