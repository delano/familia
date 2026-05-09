Documentation
~~~~~~~~~~~~~

- Added ``docs/guides/feature-normalizers.md`` describing the proposed
  ``normalizers`` feature: a declarative DSL for registering named cleanup
  lambdas on Horreum models, intended for short-lived data normalization runs
  that complement (rather than replace) the migration system. Refs #258.

AI Assistance
~~~~~~~~~~~~~

- Drafted the normalizers guide (structure, examples, generated method
  reference, and design constraints) using Claude Code, working from the API
  proposal in issue #258 and the existing relationships guide as a style
  template.
