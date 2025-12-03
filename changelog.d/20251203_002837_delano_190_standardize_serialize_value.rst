Changed
-------

- Standardized DataType serialization to use JSON encoding for type preservation, matching Horreum field behavior. All primitive values (Integer, Boolean, String, Float, Hash, Array, nil) are now consistently serialized through JSON, ensuring types are preserved across the Redis storage boundary. Familia object references continue to use identifier extraction. Issue #190.

AI Assistance
-------------

- Claude Code assisted with refactoring the serialization logic, updating test cases to verify type preservation across all data types, and ensuring consistency between DataType and Horreum serialization behavior.
