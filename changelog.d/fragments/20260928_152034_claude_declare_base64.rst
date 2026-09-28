Fixed
-----

- ``familia.gemspec`` now declares ``base64`` (``~> 0.2``) as a runtime
  dependency. ``require 'familia'`` loads ``base64`` unconditionally, and on
  Ruby 3.4+ base64 is no longer a default gem, so an application bundle that
  did not already include base64 failed at boot with ``cannot load such file
  -- base64 (LoadError)``.

AI Assistance
-------------

- The fix and the CI check were developed with AI assistance.
