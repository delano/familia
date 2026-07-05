Fixed
-----

- Nil-valued fields are no longer persisted to Valkey/Redis as the JSON string
  ``"null"``. A hash has no native NULL, so storing ``"null"`` for every declared
  field left declared fields perpetually *present*, which defeated
  ``HSETNX``/``HEXISTS``-based atomic claim ("first writer wins") patterns and
  wasted memory. Nil fields are now omitted so that field *absence* represents
  "no value" -- realigning with the behavior ``to_h_for_storage``'s own
  documentation had described all along (v1.x excluded nils; the v2.0
  type-preserving serialization rewrite started writing ``"null"`` without
  updating the docs). A field cleared to nil is now actively removed from storage
  on save (``HDEL``), so ``"unset"`` and ``nil`` are again the same observable
  state after a round trip. Hashes that still contain ``"null"`` values are
  cleaned up automatically the next time the object is saved; reads already decode
  ``"null"`` back to ``nil``, so no migration is required.

Changed
-------

- ``Horreum#to_h_for_storage`` now omits nil-valued fields, and every write path
  removes a field that has become nil rather than storing ``"null"``: the
  full-object paths (``save``, ``commit_fields``) delete now-nil declared fields,
  and the partial paths (``save_fields``, ``multi_field_update``,
  ``multi_field_fast_write``) delete a named field passed as nil. ``HMSET`` on an
  object with no non-nil fields is treated as a successful no-op instead of
  raising, since a normal object's always-present identifier field keeps its hash
  non-empty. ``to_h`` is unchanged and still returns every declared field
  (including nils) for API stability.

- ``save`` and ``commit_fields`` remain a *full-overwrite* of scalar state: after
  a save the stored hash matches the in-memory object exactly, so a field that is
  nil in memory is removed from storage. A consequence worth noting for the claim
  pattern: a field claimed out of band via ``HSETNX`` while an in-memory copy
  still holds nil for it is cleared by a full ``save``/``commit_fields`` of that
  (stale) copy. To claim a field and update the record without disturbing it, use
  the targeted writers (``save_fields``, ``multi_field_update``,
  ``multi_field_fast_write``), or ``refresh!`` before saving.

AI Assistance
-------------

- Investigation of the serialization/persistence code paths, the implementation,
  and new tryouts coverage (proving ``HSETNX``-based claims now succeed on a
  nil-declared field and that a field cleared to nil is removed from storage) were
  produced with assistance from Claude Code.
