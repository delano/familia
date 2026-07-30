Fixed
-----

- ``ConcealedString`` no longer registers a GC finalizer that could never do
  anything. ``initialize`` freezes the encrypted buffer, while the finalizer
  only cleared unfrozen strings -- mutually exclusive by construction, so the
  advertised "best-effort memory clearing" was unconditionally a no-op. The
  finalizer and the claim are gone: the class docs, ``clear!`` docs, and the
  encryption guide now state plainly that ``clear!`` drops references and
  blocks further reveals but cannot wipe memory, matching the honesty of the
  ``RedactedString`` header's memory-model caveats. Behavior is unchanged
  (the finalizer never did anything); ``ConcealedString.finalizer_proc`` is
  removed. Not exploitable -- a truth-in-advertising fix from the 2026-07-19
  internal code audit. #359

AI Assistance
-------------

- AI removed the dead finalizer path, rewrote the memory-clearing claims in
  the ``ConcealedString`` docs and the encryption guide to describe what
  ``clear!`` actually does, and verified the encrypted/transient field
  tryouts suites still pass.
