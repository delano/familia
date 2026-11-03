Changed
-------

- ``Familia::Migration::Model#migrate`` in interactive mode
  (``@interactive = true``) now raises
  ``Familia::Migration::Errors::PreconditionFailed`` instead of
  ``LoadError`` when ``pry-byebug`` is missing from the application bundle
  or fails to load, so ``Familia::Migration::Runner`` records the migration
  as ``:failed``. ``rake familia:migrate:run`` and ``familia:migrate:dry_run``
  then print the failure and exit 0, as for any other failed migration; the
  uncaught ``LoadError`` used to end them with exit status 1. familia does
  not depend on ``pry-byebug``. See ``docs/migrating/runtime-dependencies.md``.

AI Assistance
-------------

- The change and regression tests were developed with AI assistance.
