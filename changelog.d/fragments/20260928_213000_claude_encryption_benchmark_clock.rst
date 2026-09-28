Fixed
-----

- ``Familia::Encryption.benchmark`` no longer requires ``benchmark``, a
  bundled gem from Ruby 4.0, so it no longer raises ``cannot load such file
  -- benchmark (LoadError)`` under Bundler on Ruby 4.0 when the application
  bundle lacks ``benchmark``. It times providers with
  ``Process.clock_gettime(Process::CLOCK_MONOTONIC)``.

AI Assistance
-------------

- The fix and regression test were developed with AI assistance.
