Fixed
-----

- Restored objid provenance tracking when loading objects from Redis. The ``ObjectIdentifier`` feature now infers the generator type (:uuid_v7, :uuid_v4, :hex) from the objid format, enabling dependent features like ``ExternalIdentifier`` to derive external identifiers from loaded objects. PR #131

AI Assistance
-------------

- Claude Code assisted with implementing the ``infer_objid_generator`` method and updating the setter logic in ``lib/familia/features/object_identifier.rb``.
