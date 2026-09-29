Changed
-------

- ``require 'familia'`` no longer loads ``base64``, and ``familia.gemspec``
  does not depend on it. Applications that call ``Base64`` must
  ``require 'base64'`` themselves and, on Ruby 3.4+, list ``base64`` in their
  Gemfile. See ``docs/migrating/runtime-dependencies.md``.

Fixed
-----

- ``require 'familia'`` no longer fails with ``cannot load such file --
  base64 (LoadError)`` on Ruby 3.4+ in an application bundle without
  ``base64``.

AI Assistance
-------------

- The fix and the CI check were developed with AI assistance.
