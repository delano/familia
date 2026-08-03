Fixed
-----

- Removed the redundant post-save ``update_all_indexes`` re-run from the
  ``Relationships`` feature's ``save`` override (follow-up to #306). Class-level
  index maintenance is fully handled inside the save transaction by
  ``auto_update_class_indexes``, so the post-``EXEC`` re-run only re-claimed and
  re-wrote the same values -- costing an extra ``EXISTS`` probe, a
  ``claim_field`` ``EVAL``, and a second ``MULTI`` per unique index, and able to
  raise ``RecordExistsError``/``PersistenceError`` *after* the save had already
  committed. #307

AI Assistance
-------------

- AI deleted the ``save`` override in
  ``Familia::Features::Relationships::ModelInstanceMethods`` and added
  regression coverage asserting that a class-level ``unique_index`` save queues
  its ``HSET`` inside the save ``MULTI``/``EXEC`` and issues no index writes
  after the transaction commits.
