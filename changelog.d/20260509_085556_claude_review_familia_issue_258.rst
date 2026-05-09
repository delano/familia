Added
-----

- ``feature :normalizers`` -- a lightweight, declarative DSL for registering
  temporary record-cleanup rules on ``Familia::Horreum`` classes. Distinct from
  ``Familia::Migration``: no versioning, no execution tracking, no dry-run
  mode. Register named blocks with ``normalizer :name do |record| ... end``
  and run them via ``MyModel.normalize!`` (all) or
  ``MyModel.normalize!(:name)`` (one). Iterates the class-level ``instances``
  sorted set in ``batch_size:``-bounded slices (default 100), isolates
  per-record errors, and returns a stats hash
  (``{ scanned:, modified:, errors:, error_messages: }``) per normalizer.
  Saves remain explicit -- the normalizer block is responsible for calling
  ``save`` -- which keeps the feature appropriate for the "run nightly for a
  few days, then remove" workflow it was designed for. (#258)

AI Assistance
-------------

- Feature module, tryouts coverage, and this fragment drafted by Claude
  (Anthropic Opus 4.7) from the issue specification, with a human review pass
  before merge. (#258)
