Removed
-------

- Dropped the unused ``csv`` and ``stringio`` runtime dependencies from the
  gemspec. Neither was referenced anywhere in the shipped library — no
  ``require``, no ``CSV.`` call, no ``StringIO`` reference in ``lib/``,
  ``bin/``, or ``examples/`` — so both were leftovers from code paths that no
  longer exist. Installing familia no longer pulls ``csv`` into a consumer's
  bundle.

  The ``stringio`` entry was the more pressing of the two: it pinned
  ``>= 3.1.1, < 3.3.0`` on a Ruby **default gem**, so once a Ruby release ships
  stringio 3.3.0 or newer, every consumer of familia on that Ruby would hit an
  unresolvable dependency for a gem the library never used. Removing the
  constraint takes that future breakage off the table.

  Nothing needs to change on the consumer side. Both gems ship with Ruby, and
  familia never loaded either, so an application that uses ``CSV`` or
  ``StringIO`` in its own code is unaffected — though an application that was
  relying on familia to declare ``csv`` for it should now declare it directly.
  Test files under ``try/`` that use ``StringIO`` keep working: it is a default
  gem and ``require 'stringio'`` resolves without a gemspec entry. #354

AI Assistance
-------------

- Claude Code verified that neither dependency had any caller in the shipped
  library, removed both from ``familia.gemspec``, regenerated ``Gemfile.lock``
  (``stringio`` remains in the lockfile as a transitive dependency of ``psych``,
  now uncapped), and confirmed the full tryouts suite stays green.
