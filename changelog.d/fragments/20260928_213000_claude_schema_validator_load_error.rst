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
  record passed. ``Familia::Migration::Model#migrate`` raises it at the
  first record it validates, through ``validate_before_transform?``,
  ``validate_after_transform?`` or a ``#validate_schema`` call in
  ``#process_record``, in dry runs and actual runs.
  ``Familia::Migration::Pipeline`` does not run the validation hooks; it
  raises only when ``#should_process?``, ``#build_update_fields`` or
  ``#execute_update`` calls ``#validate_schema``, and only in an actual
  run. Where ``#migrate`` raises it, ``Familia::Migration::Base.run`` and
  ``.cli_run`` let it propagate, and ``Familia::Migration::Runner`` records
  the migration as ``:failed`` and not applied.
  When ``json_schemer`` itself cannot be loaded, validation still warns and
  is disabled. See ``docs/migrating/runtime-dependencies.md``.

AI Assistance
-------------

- The change and regression tests were developed with AI assistance.
