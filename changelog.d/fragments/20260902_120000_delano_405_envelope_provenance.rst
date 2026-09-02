Security
--------

- Encrypted field setters no longer duck-type the assigned value. Previously
  any value that parsed as JSON with the envelope keys (``algorithm``,
  ``nonce``, ``ciphertext``, ``auth_tag``, ``key_version``) was stored
  verbatim, so caller-supplied plaintext shaped like an envelope landed at
  rest unencrypted (and unreadable). A value is now taken verbatim only when
  wrapped in the new ``Familia::Encryption::StoredEnvelope`` marker, which the
  hydration path applies via ``EncryptedFieldType#deserialize``; every other
  assignment (setter, fast writer, ``apply_fields``, keyword construction) is
  encrypted whatever it looks like. ``multi_field_update`` and
  ``multi_field_fast_write`` were unaffected: they already raise
  ``ArgumentError`` for anything but a ``ConcealedString``. (#405)

Changed
-------

- ``Familia::FieldType#deserialize(value, record)`` is now called on the
  storage-to-object path (``load``, ``find_by_id``, ``refresh!``,
  ``naive_refresh``) for every persistent field, after JSON decoding and before
  the setter. It was previously defined but never invoked. Custom field types
  that override it will now see stored values pass through it. (#405)
- Constructing a record with raw envelope JSON as a keyword argument
  (``Model.new(secret: envelope_json)``) now encrypts that JSON as plaintext.
  Rehydrate from a raw storage hash with ``naive_refresh`` instead. (#405)

AI Assistance
-------------

- The provenance-marker design, the hook wiring and the tests were developed
  with AI assistance.
