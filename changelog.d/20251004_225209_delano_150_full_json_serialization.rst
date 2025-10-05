.. Familia v2.0 - Full JSON Serialization Implementation
..
.. Issue #150: https://github.com/delano/familia/issues/150
..

Changed
-------

- **BREAKING**: Implemented full JSON serialization for all Horreum field values to preserve Ruby types across Redis storage boundary. All field values (Integer, Boolean, String, Hash, Array, Float, nil) are now JSON-encoded for storage and JSON-decoded on retrieval, ensuring type preservation in round-trip operations.

- **BREAKING**: Fixed ``initialize_with_keyword_args`` to properly handle ``false`` and ``0`` values during object initialization. Previously, falsy values were incorrectly skipped due to truthiness checks. Now uses explicit nil checking with ``fetch`` to preserve all non-nil values including ``false`` and ``0``.

Removed
-------

- **BREAKING**: Removed ``dump_method`` and ``load_method`` configuration options from ``Familia::Base`` and ``Familia::Horreum::Definition``. JSON serialization is now hard-coded for consistency and type safety. Custom serialization methods are no longer supported.

Fixed
-----

- Fixed type coercion bugs where Integer fields (e.g., ``age: 35``) became Strings (``"35"``) and Boolean fields (e.g., ``active: true``) became Strings (``"true"``) after database round-trips. All primitive types now maintain their original types through ``find_by_dbkey``, ``refresh!``, and ``batch_update`` operations.

- Fixed ``deserialize_value`` to return all JSON-parsed types instead of filtering to Hash/Array only. This enables proper deserialization of primitive types (Integer, Boolean, Float, String) from Redis storage.

- Added JSON deserialization in ``find_by_dbkey`` before object instantiation to ensure loaded objects receive properly typed field values rather than raw Redis strings.

Documentation
-------------

- Added comprehensive type preservation test suite (``try/unit/horreum/json_type_preservation_try.rb``) with 30 test cases covering Integer, Boolean, String, Float, Hash, Array, nested structures, nil handling, empty strings, zero values, round-trip consistency, ``batch_update``, and ``refresh!`` operations.

AI Assistance
-------------

- Claude Code (claude-sonnet-4-5) provided implementation guidance, identified the ``initialize_with_keyword_args`` falsy value bug, wrote comprehensive test suite, and coordinated multi-file changes across serialization, management, and base modules.
