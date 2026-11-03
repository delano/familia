Changed
-------

- ``Horreum#refresh!`` and ``Horreum#refresh`` raise
  ``Familia::KeyNotFoundError`` when the record's key does not exist, as
  documented, and leave the object unchanged. They returned normally and
  cleared dirty tracking. Code that refreshes a record that may not be saved
  yet must rescue the error or use ``find_by_id``, which returns ``nil``. See
  ``docs/migrating/refresh.md``. (#443)
- ``HashKey#refresh!`` and ``HashKey#refresh`` raise
  ``Familia::KeyNotFoundError`` for a missing key instead of
  ``Redis::CommandError``
  (``ERR wrong number of arguments for 'hmset' command``). Update ``rescue``
  clauses. See ``docs/migrating/refresh.md``. (#443)

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
