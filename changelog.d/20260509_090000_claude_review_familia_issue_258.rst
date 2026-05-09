Added
-----

- ``feature :housekeeping`` -- a tiny DSL for declaring named cleanup blocks
  ("chores") on a ``Familia::Horreum`` model and running them against a
  single instance. Registration uses ``chore :name do |record| ... end``;
  execution uses ``record.tidy!`` (all chores) or ``record.tidy!(:name)``
  (one chore) and returns ``{ name => block_return_value }``. The feature
  intentionally does not iterate, batch, aggregate stats, or handle errors
  -- iteration strategy, scheduling, and error handling are the consumer
  application's responsibility. Use this for transient cleanup tasks ("run
  nightly for a few days, then remove"); use ``Familia::Migration`` for
  versioned, one-shot transformations. (#258)

AI Assistance
-------------

- Feature module, tryouts coverage, and this fragment drafted by Claude
  (Anthropic Opus 4.7) from the issue specification, with a human review
  pass before merge. (#258)
