Changed
-------

- ``familia.gemspec`` requires ``oj`` ``~> 3.16, >= 3.16.2`` (was
  ``~> 3.16``) and ``json_schemer`` ``~> 2.2`` (was ``~> 2.0``). Bundles
  that pin an older ``oj`` or ``json_schemer`` no longer resolve. The
  excluded ``json_schemer`` 2.0.0 to 2.1.1 require ``base64`` without
  declaring it; now that ``require 'familia'`` no longer loads ``base64``,
  they would fail to load on Ruby 3.4+ in a bundle without it. See
  ``docs/migrating/runtime-dependencies.md``.

Fixed
-----

- On Ruby 3.4+, ``require 'familia'`` no longer fails with ``cannot load
  such file -- bigdecimal (LoadError)`` when the bundle resolves ``oj``
  3.16.0 or 3.16.1.

Documentation
-------------

- The schema validation guide no longer tells applications to add
  ``json_schemer`` to their Gemfile. familia declares it.

AI Assistance
-------------

- The change and regression tests were developed with AI assistance.
