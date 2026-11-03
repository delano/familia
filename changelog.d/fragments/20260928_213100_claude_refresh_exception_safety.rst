Fixed
-----

- ``Horreum#refresh!`` and ``Horreum#refresh`` leave the object as it was
  when a field setter raises on a stored value, for example
  ``Familia::EncryptionError`` for an encrypted field whose stored envelope
  names an algorithm that is not available. Field values, transient fields
  and dirty tracking are restored before the error propagates. They left the
  fields before the failing one assigned, transient fields reset, and the
  assigned fields marked dirty.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
