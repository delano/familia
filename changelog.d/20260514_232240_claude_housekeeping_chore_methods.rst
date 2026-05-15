Changed
~~~~~~~

- ``housekeeping`` feature: split the dual-purpose ``tidy!`` into two
  explicit instance methods. ``do_chore!(name)`` runs a single named
  chore and returns the block's raw return value (no longer wrapped
  in a ``{name => result}`` hash). ``do_chores!`` runs every
  registered chore and returns the ``{name => result}`` hash.
  ``tidy!`` is preserved as an alias of ``do_chores!`` for backwards
  compatibility with the 2.7.0 API.

AI Assistance
~~~~~~~~~~~~~

- Method split, alias wiring, doc updates and expanded tryouts
  coverage authored with Claude Code.
