Added
-----

- Class-level multi-value indexing with ``multi_index :field, :index_name`` (``within: :class`` is now the default). Creates class methods like ``Model.find_all_by_field(value)`` and ``Model.sample_from_field(value, count)`` for grouping objects by field values at the class level.

Changed
-------

- ``multi_index`` now defaults to ``within: :class`` instead of requiring a scope class. Existing instance-scoped indexes (``within: SomeClass``) continue to work unchanged.

AI Assistance
-------------

- Claude Opus 4.5 assisted with implementation design, code generation, test creation, and debugging of serialization consistency issues between DataType methods and raw Redis commands.
