Added
-----

- Introduced ``reference: true`` option for DataType collection declarations.
  Collections with this option store member identifiers raw instead of
  JSON-encoding them, resolving the semantic mismatch between field storage
  (type-preserving JSON) and collection member storage (identity references).

Fixed
-----

- Fixed serialization mismatch in ``instances`` sorted set where
  ``persist_to_storage`` passed a string identifier (JSON-encoded as
  ``"\"abc-123\""``), while direct calls passed Familia objects (stored raw as
  ``abc-123``). Now passes ``self`` to ``instances.add`` and declares
  ``reference: true`` on the collection, ensuring consistent storage.
  (`#215 <https://github.com/delano/familia/issues/215>`_)

- Fixed ``UnsortedSet#pop`` returning raw Redis strings instead of deserialized
  values.

- Fixed ``UnsortedSet#move`` passing raw values to Redis instead of serializing
  them.

- Fixed ``SortedSet#increment`` truncating scores to integer (``.to_i``) instead
  of preserving float precision (``.to_f``).

Documentation
-------------

- Added collection member serialization guide to ``docs/guides/field-system.md``
  explaining the distinction between field serialization (JSON for type
  preservation) and collection member serialization (raw identifiers for
  reference collections).

AI Assistance
-------------

- Claude assisted with systematic audit of all ``.add()`` call sites and
  collection declarations across the codebase, identifying the root cause of the
  serialization mismatch and the three additional DataType method bugs discovered
  during the audit.
