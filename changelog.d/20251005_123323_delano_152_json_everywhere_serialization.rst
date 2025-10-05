.. Removes string-as-is optimization, implements pure JSON serialization for type safety

Fixed
-----

- Fixed encrypted fields with ``category: :encrypted`` appearing in ``to_h()`` output. These fields now correctly set ``loggable: false`` to prevent accidental exposure in logs, APIs, or external interfaces. PR #152

Changed
-------

- **String serialization now uses JSON encoding**: All string values are JSON-encoded during storage (wrapped in quotes) for consistent type preservation. The lenient deserializer handles both new JSON-encoded strings and legacy plain strings automatically. PR #152

Security
--------

- Encrypted fields defined via ``field :name, category: :encrypted`` now properly excluded from ``to_h()`` serialization, matching the security behavior of ``encrypted_field``. PR #152

AI Assistance
-------------

- Issue analysis, implementation guidance, test verification, and documentation for JSON serialization changes and encrypted field security fix.
