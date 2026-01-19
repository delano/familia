Fixed
-----

- Fixed relationship reverse lookup methods failing when a class declares an explicit
  ``prefix`` that differs from its computed ``config_name``. For example, a class with
  ``prefix :customdomain`` (no underscore) but ``config_name`` returning ``"custom_domain"``
  (with underscore) now correctly finds related instances. PR #207

AI Assistance
-------------

- Claude Opus 4.5 assisted with root cause analysis, coordinating multiple agents to
  explore the codebase, implementing the fix across 5 locations, and writing comprehensive
  test coverage (53 test cases) for various prefix/config_name scenarios.
