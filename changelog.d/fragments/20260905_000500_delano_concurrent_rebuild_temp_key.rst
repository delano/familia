Security
--------

- Made ``AtomicOperations.build_temp_key`` append a random nonce to the timestamp suffix so concurrent rebuilds of the same index started within one second no longer share a temporary key.
