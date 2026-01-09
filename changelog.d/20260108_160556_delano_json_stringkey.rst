Added
-----

- New ``JsonStringKey`` DataType for type-preserving string storage. Unlike
  ``StringKey`` which uses raw strings (for INCR/DECR support), ``JsonStringKey``
  uses JSON serialization to preserve Ruby types (Integer, Float, Boolean, Hash,
  Array) across the Redis storage boundary. Registered as ``:json_string`` and
  ``:json_stringkey``, enabling DSL methods like ``json_string :metadata`` and
  ``class_json_string :last_synced_at``.

AI Assistance
-------------

- Claude Opus 4.5 assisted with implementation design, code generation, and
  comprehensive test coverage (67 test cases) for the JsonStringKey feature.
