Documentation
-------------

- Added ``docs/migrating/refresh.md`` covering the ``Horreum#refresh!``,
  ``Horreum#refresh``, ``HashKey#refresh!`` and ``HashKey#refresh`` changes.
- Corrected the ``docs/overview.md`` transient-field examples. They called
  ``reload``, which does not exist, instead of ``refresh!``. The
  ``LoginAttempt`` example also used ``redacted_field`` and
  ``RedactedString#reveal``, which do not exist, declared no identifier, and
  read a transient value after ``refresh!``, which resets it to nil. The
  ``SecureModel`` example passed two names to ``field``,
  ``encrypted_field`` and ``transient_field``, which take one, declared no
  identifier or encryption keys, called ``create`` instead of ``create!``,
  and called ``ConcealedString#reveal`` without a block.

AI Assistance
-------------

- The documentation changes were drafted with AI assistance.
