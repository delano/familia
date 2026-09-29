Added
-----

- ``Horreum#deserialize_value`` accepts ``dbkey:``, the key the value was read
  from. The error log entry for a value that is not JSON names it.

Fixed
-----

- ``find_by_id``, ``find_by_dbkey``, ``load_multi``, ``load_multi_by_keys``
  and ``Horreum#naive_refresh`` no longer generate an ``objid`` or send
  ``HDEL`` to ``objid_lookup`` or ``extid_lookup`` when a stored value is not
  JSON and the identifier reads ``objid`` or ``extid``. The error log entry
  for such a value no longer computes the identifier. It names the key the
  caller passes, the key built from a Symbol or String identifier field's
  current value, or ``no dbkey``. It named a key built from the generated
  ``objid``.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
