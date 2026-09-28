Documentation
-------------

- Corrected the ``docs/overview.md`` transient-field examples. They called
  ``reload``, which does not exist, instead of ``refresh!``. The
  ``LoginAttempt`` example also used ``redacted_field`` and
  ``RedactedString#reveal``, which do not exist, declared no identifier, and
  read a transient value after ``refresh!``, which resets it to nil.

AI Assistance
-------------

- The documentation changes were drafted with AI assistance.
