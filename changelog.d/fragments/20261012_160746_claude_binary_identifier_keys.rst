Added
-----

- ``Familia.normalize_key_encoding(str)``: returns ``str`` relabelled with the
  encoding redis-client gives a key or member with the same bytes, UTF-8 when
  the bytes are valid UTF-8 and BINARY otherwise. The bytes are unchanged.

Changed
-------

- ``Familia.join``, and so ``Familia.dbkey``, ``Horreum.dbkey`` and every
  ``dbkey`` derived from them, returns the key in the encoding of
  ``Familia.normalize_key_encoding``. Previously the result kept the encoding
  ``Array#join`` gave it: a key built from an ASCII prefix and a BINARY
  identifier was BINARY even when its bytes were valid UTF-8, and a key built
  from a UTF-8 identifier with invalid bytes was UTF-8 while the same key
  built from the member read back from the server was BINARY, so the two were
  neither ``==`` nor equal as Hash keys. Keys whose parts are valid UTF-8 are
  unchanged.

Fixed
-----

- ``Familia.join`` no longer raises ``Encoding::CompatibilityError`` when the
  parts carry non-ASCII bytes in incompatible encodings, such as a non-ASCII
  class ``prefix`` (e.g. ``prefix 'équipe'``) with a BINARY identifier (not
  valid UTF-8). The parts are joined as bytes. ``exists?``, ``load`` and
  ``rebuild_instances`` now work for such records.
- ``Horreum.extract_identifier_from_key`` compares the key with the prefix and
  suffix as bytes instead of raising ``Encoding::CompatibilityError`` for a
  BINARY key under a non-ASCII prefix.
- ``audit_multi_indexes`` no longer raises ``Encoding::CompatibilityError``
  for an instance-scoped ``multi_index`` whose scope class has a non-ASCII
  ``prefix`` and a scope identifier that is not valid UTF-8. Bucket keys are
  parsed as bytes, and the expected bucket key is built like the
  ``<index_name>_for`` factory builds it, so it matches the stored key.
- ``DatabaseLogger`` no longer raises ``Encoding::CompatibilityError`` after a
  command whose arguments are in incompatible encodings, or, with
  unstructured logging, after a command with a non-ASCII BINARY argument.
  Previously the command ran but the caller received the error.
  ``DatabaseLogger.command_string`` renders such arguments, and arguments
  that are not valid UTF-8, as UTF-8 with invalid bytes escaped as ``\xNN``,
  so captured commands with BINARY payloads read ``\xFF`` where they held the
  raw byte.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
