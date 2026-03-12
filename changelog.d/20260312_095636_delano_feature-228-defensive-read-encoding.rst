Fixed
-----

- ``Manager#decrypt`` no longer returns ASCII-8BIT strings. Decrypted plaintext
  is now force-encoded to UTF-8 by default, fixing compatibility with json 2.18+
  (which rejects non-UTF-8 strings) and preventing a hard error in json 3.0.
  When an ``encoding`` field is present in the encrypted envelope, that encoding
  is used instead. Fixes `#228 <https://github.com/delano/familia/issues/228>`_.

- ``EncryptedData.from_json`` and ``validate!`` now filter unknown keys from
  parsed envelopes before instantiation. This prevents ``ArgumentError`` when
  reading envelopes written by future versions that include additional fields
  (e.g. ``encoding``, ``compression``).

AI Assistance
-------------

- Claude implemented the Phase 1 defensive read strategy, added the ``encoding``
  field to ``EncryptedData`` with nil default and ``to_h.compact`` for clean
  serialization, and wrote 22 test cases covering encoding round-trips, legacy
  envelope backward compatibility, unknown key filtering, and edge cases (nil
  input, bogus encoding names, binary ASCII-8BIT content).
  PR `#230 <https://github.com/delano/familia/pull/230>`_.
