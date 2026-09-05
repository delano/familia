Security
--------

- Assigning plaintext to an encrypted field now raises ``Familia::NoIdentifier``
  when the record has no identifier, preventing ciphertext from becoming
  undecryptable after an identifier is assigned.
