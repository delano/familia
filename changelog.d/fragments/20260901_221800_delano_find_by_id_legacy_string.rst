Fixed
-----

- ``Model.find_by_id``, ``find_by_dbkey``, and ``load_multi`` no longer raise
  ``Familia::NoIdentifier`` when the stored hash contains a field value that
  is not valid JSON (a legacy plain string written by a pre-JSON serializer or
  by hand via ``HSET``). ``log_deserialization_issue`` computed ``dbkey`` for
  its log message before any field setter had run on the freshly allocated
  instance, so the identifier was still nil. The lookup now falls back to
  ``no dbkey`` and the record loads with the raw string as the field value,
  logging the intended ``Legacy plain string in ...`` error. ``refresh!`` was
  unaffected because the instance already had its identifier.

AI Assistance
-------------

- The fix and regression test were developed with AI assistance.
