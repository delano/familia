Changed
-------

- ``Familia::Migration::Model#migrate`` in interactive mode
  (``@interactive = true``) now raises
  ``Familia::Migration::Errors::PreconditionFailed`` naming ``pry-byebug``
  when the application bundle lacks it, instead of ``LoadError``, so
  ``Familia::Migration::Runner`` records the migration as ``:failed``.
  familia does not depend on ``pry-byebug``.

AI Assistance
-------------

- The change and regression tests were developed with AI assistance.
