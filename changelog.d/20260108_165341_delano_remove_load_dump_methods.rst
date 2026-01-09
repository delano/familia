Removed
-------

- **BREAKING**: Removed ``dump_method`` and ``load_method`` configuration options
  from ``Familia::Base``, ``Familia::Horreum``, and ``Familia::DataType``. JSON
  serialization via ``to_json``/``from_json`` is now hard-coded for consistency
  and type safety. Custom serialization methods are no longer supported.

AI Assistance
-------------

- Claude Opus 4.5 coordinated parallel agents (backend-dev, qa-automation-engineer)
  to systematically remove all references across 9 files while maintaining test
  coverage (3,162 tests passing).
