Changed
-------

- ``Familia::Migration::Model#migrate`` in interactive mode
  (``@interactive = true``) now raises
  ``Familia::Migration::Errors::PreconditionFailed`` instead of
  ``LoadError`` when ``pry-byebug`` is missing from the application bundle
  or fails to load, so ``Familia::Migration::Runner`` records the migration
  as ``:failed``. familia does not depend on ``pry-byebug``. See
  ``docs/migrating/runtime-dependencies.md``.

AI Assistance
-------------

- The change and regression tests were developed with AI assistance.
