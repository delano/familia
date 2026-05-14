Added
~~~~~

- New ``housekeeping`` feature for ``Familia::Horreum``: a declarative DSL
  (``chore :name do |obj| ... end``) for registering named cleanup blocks on
  a model class, plus an instance method ``tidy!`` that runs all (or one)
  registered chore against a single object. The feature owns registration
  and per-instance execution only -- iteration, batching, scheduling and
  error aggregation are the consumer application's responsibility, keeping
  it distinct from ``Familia::Migration`` (which is for versioned, one-shot
  transformations). Resolves #258.

Documentation
~~~~~~~~~~~~~

- Added ``docs/guides/feature-housekeeping.md`` covering the API, the
  ``housekeeping`` vs ``migration`` vs defensive-setter trade-off,
  generated method reference, design constraints, and common patterns
  (multiple chores, sequential steps in one chore, tracking modified
  records, error aggregation).

AI Assistance
~~~~~~~~~~~~~

- Drafted the housekeeping feature module, the tryouts test suite, and the
  guide using Claude Code, working from the API proposal in issue #258 and
  the existing ``feature-relationships.md`` and ``safe_dump.rb`` as style
  templates.
