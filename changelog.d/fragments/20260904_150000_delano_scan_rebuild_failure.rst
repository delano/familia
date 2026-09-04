Security
--------

- SCAN-based unique-index rebuilds now abort when a batch cannot be loaded or
  written. The failed rebuild preserves the live index instead of replacing it
  with an incomplete temporary index.

AI Assistance
-------------

- The failure propagation change and regression coverage were developed with AI
  assistance.
