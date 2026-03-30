Fixed
-----

- ``build_aad`` now produces consistent AAD (Additional Authenticated Data)
  regardless of whether the record has been persisted. Previously, encrypted
  fields with ``aad_fields`` used different AAD computation paths before and
  after save, making ``reveal`` fail on any record created via ``create!``.
  PR #232

AI Assistance
-------------

- Claude assisted with implementing the fix, updating affected tests, and
  writing the round-trip regression test. The issue analysis, root cause
  identification, and suggested fix were provided in the issue by the author.
