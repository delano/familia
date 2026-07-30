Fixed
-----

- ``update_in_<scope>_<index_name>`` (instance-scoped ``unique_index`` with
  ``within:``) no longer leaks an index claim when called on an unsaved
  record. The generated method claimed the new field value via the CAS
  *before* running the persisted-record guard, so when
  ``_ensure_persisted_before_index_write!`` raised
  ``Familia::PersistenceError`` the already-written claim was never
  released -- the value stayed pointing at a record that did not exist in
  the database and no other record could ever claim it. The guard now runs
  before the claim, matching the ordering the sibling generated methods
  (``add_to_*``, ``add_to_class_*``, ``update_in_class_*``) already used.
  Not reachable through the normal save flow (inside a save ``MULTI`` the
  guard short-circuits and the claim path is skipped); it required a direct
  call to the generated method on an unpersisted record. Found by the
  2026-07-30 security audit. #370

AI Assistance
-------------

- AI reordered the persisted-record guard ahead of the CAS claim in the
  generated ``update_in_<scope>_<index_name>`` method and added regression
  coverage asserting that a rejected unsaved record leaves no claim behind
  and that the value remains claimable by a persisted record.
