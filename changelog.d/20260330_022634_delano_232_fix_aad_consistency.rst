Fixed
-----

- ``build_aad`` no longer uses ``.compact`` on AAD field values. Previously,
  nil fields were silently dropped, shifting later values left and producing
  a different hash once the field was populated. Now each field is coerced
  via ``.to_s`` so that nil and empty string both occupy a fixed position
  in the joined AAD string. Issue #232, PR #234.

AI Assistance
-------------

- Claude implemented the ``.compact`` removal fix, updated the existing
  nil-vs-empty-string test expectation, and added positional stability
  tests for multi-field AAD. The issue analysis was provided in
  conversation by the author.
