Removed
-------

- ``familia.gemspec`` no longer declares ``connection_pool``, and
  ``require 'familia'`` no longer requires it itself. familia calls no
  ``connection_pool`` API, and it no longer limits the ``connection_pool``
  version an application resolves (previously ``>= 2.4, < 4.0``).
  Applications that pass a ``ConnectionPool`` to
  ``Familia.connection_provider`` should list ``connection_pool`` in their
  Gemfile and require it. See ``docs/migrating/runtime-dependencies.md``.

AI Assistance
-------------

- The change was developed with AI assistance.
