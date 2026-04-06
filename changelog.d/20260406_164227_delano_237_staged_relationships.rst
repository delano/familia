Added
-----

- Added ``staged:`` option to ``participates_in`` for invitation workflows where
  through models must exist before participants. Creates a staging sorted set
  alongside the active membership set with three new operations:
  ``stage_members_instance``, ``activate_members_instance``, ``unstage_members_instance``.
  Staged models use UUID keys; activated models use composite keys.
  (`#237 <https://github.com/delano/familia/issues/237>`_)

- Added ``StagedOperations`` module in ``lib/familia/features/relationships/participation/``
  for staging lifecycle management with lazy cleanup for ghost entries.

- Added ``staged?`` and ``staging_collection_name`` methods to ``ParticipationRelationship``.

Changed
-------

- **Breaking change**: Through models in staged relationships use UUID keys during staging,
  composite keys after activation. The staged model is destroyed during activation --
  any references to it become invalid. Application code calling ``accept!`` on
  staged memberships should capture and use the returned activated model rather
  than the original staged model.

- Extended ``participates_in`` signature to accept ``staged:`` option (Symbol or nil).
  Validation ensures ``staged:`` requires ``through:`` option.

AI Assistance
-------------

- Claude assisted with architecture design, identifying the impedance mismatch between
  relational ORM patterns and Redis's materialized indexes, analyzing transaction
  boundaries, and designing the separation between ``StagedOperations`` and
  ``ThroughModelOperations`` modules.
