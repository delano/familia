Added
-----

- ``Familia::SchemaValidatorLoadError``, a ``Familia::Problem``. Its
  ``cause`` is the ``LoadError`` that stopped ``json_schemer`` from loading.

Changed
-------

- Schema validation (``Familia::SchemaRegistry.validate`` and
  ``.validate!``, the ``schema_validation`` feature's instance methods, and
  ``Familia::Migration::Base#validate_schema`` and ``#validate_schema!``)
  raises ``Familia::SchemaValidatorLoadError`` when ``json_schemer`` is
  installed but one of its own requires fails. It previously warned
  ``json_schemer gem not installed`` and disabled validation, so every
  record passed. With validation hooks on,
  ``Familia::Migration::Model#migrate`` raises it at the first record it
  validates. ``Familia::Migration::Base.run`` and ``.cli_run`` let it
  propagate, and ``Familia::Migration::Runner`` records the migration as
  ``:failed`` and not applied.
  When ``json_schemer`` itself cannot be loaded, validation still warns and
  is disabled. See ``docs/migrating/runtime-dependencies.md``.

AI Assistance
-------------

- The change and regression tests were developed with AI assistance.
