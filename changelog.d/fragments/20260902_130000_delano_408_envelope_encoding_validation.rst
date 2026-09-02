Security
--------

- The ``encoding`` field of an encryption envelope is now validated before it
  is applied to the decrypted plaintext. It is the one envelope field that is
  neither covered by the AEAD tag nor checked by ``validate_decryptable!``, so
  a rewritten value used to reach ``force_encoding`` directly: an unknown name
  raised ``ArgumentError`` (a non-string raised ``TypeError``) which the
  generic rescue in ``Manager#decrypt`` reported as ``Decryption failed``,
  indistinguishable from corrupted ciphertext. The value must now be a String
  in ``Familia::Encryption::ENVELOPE_ENCODINGS`` (``Encoding.name_list`` minus
  the host-dependent ``locale``, ``external``, ``internal`` and ``filesystem``
  pseudo names). Anything else raises a defined
  ``EncryptionError: Unsupported encoding`` from ``validate_decryptable!``,
  ``Manager#decrypt`` (before any key derivation) and ``ConcealedString``
  wrapping, and ``decryptable?`` returns false. Envelopes without the field
  still decrypt as UTF-8. Binding the field into the AAD so that a
  valid-but-wrong name is also rejected remains open; it needs a new envelope
  version. (#408)

AI Assistance
-------------

- The allowlist placement (on ``EncryptedData`` so every validation entry
  point shares it) and the accompanying tests were developed with AI
  assistance.
