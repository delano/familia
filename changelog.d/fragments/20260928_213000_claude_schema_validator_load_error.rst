Changed
-------

- Schema validation (``Familia::SchemaRegistry.validate`` and the methods
  that call it) re-raises a ``LoadError`` raised while ``json_schemer`` loads
  one of its own dependencies. It previously warned ``json_schemer gem not
  installed`` and disabled validation, so every record validated. When
  ``json_schemer`` itself cannot be loaded, validation still warns and is
  disabled.

AI Assistance
-------------

- The change and regression tests were developed with AI assistance.
