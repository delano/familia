Fixed
-----

- A record whose identifier field holds an Integer can be saved more than once
  when its class declares a ``unique_index``. The generated
  ``guard_unique_<index>!`` compared the String read back from the index with
  the Integer identifier, so every save after the first raised
  ``Familia::RecordExistsError`` naming the record itself as the owner. The
  instance-scoped guard behind ``add_to_<scope>_<index>`` had the same
  mismatch and refused a second add of the same record. Both guards now
  compare the identifier's string form.

AI Assistance
-------------

- The fix and regression tests were developed with AI assistance.
