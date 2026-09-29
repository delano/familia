Changed
-------

- ``familia.gemspec`` requires ``oj`` ``~> 3.16, >= 3.16.5`` (was
  ``~> 3.16``) and ``json_schemer`` ``~> 2.2`` (was ``~> 2.0``). Bundles
  that pin an older ``oj`` or ``json_schemer`` no longer resolve. See
  ``docs/migrating/runtime-dependencies.md``.

Fixed
-----

- On Ruby 3.4+, ``require 'familia'`` no longer fails with ``cannot load
  such file -- bigdecimal (LoadError)`` or warns that ``ostruct`` was loaded
  from the standard library when the bundle resolves ``oj`` 3.16.0 to
  3.16.4. Schema validation is no longer disabled with a ``json_schemer gem
  not installed`` warning when the bundle resolves ``json_schemer`` 2.0.0 to
  2.1.1.

Documentation
-------------

- The schema validation guide no longer tells applications to add
  ``json_schemer`` to their Gemfile. familia declares it.

AI Assistance
-------------

- The change and regression tests were developed with AI assistance.
