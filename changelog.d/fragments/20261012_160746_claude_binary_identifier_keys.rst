Fixed
-----

- ``Familia.join``, and so ``Familia.dbkey`` and ``Horreum.dbkey``, no longer
  raises ``Encoding::CompatibilityError`` when the parts carry non-ASCII bytes
  in incompatible encodings, such as a non-ASCII class ``prefix`` (e.g.
  ``prefix 'équipe'``) with a BINARY identifier (not valid UTF-8). The parts
  are joined as bytes and the result is BINARY. Results for parts with
  compatible encodings are unchanged. ``exists?``, ``load`` and
  ``rebuild_instances`` now work for such records.
- ``Horreum.extract_identifier_from_key`` compares the key with the prefix and
  suffix as bytes and returns the identifier in the key's encoding, instead of
  raising ``Encoding::CompatibilityError`` for a BINARY key under a non-ASCII
  prefix.
- ``DatabaseLogger`` no longer raises ``Encoding::CompatibilityError`` after a
  command whose arguments are in incompatible encodings, or, with
  unstructured logging, after a command with a non-ASCII BINARY argument.
  Previously the command ran but the caller received the error.
  ``DatabaseLogger.command_string`` now renders such arguments as UTF-8 with
  invalid bytes escaped as ``\xNN``, so captured commands with BINARY
  payloads read ``\xFF`` where they held the raw byte.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
