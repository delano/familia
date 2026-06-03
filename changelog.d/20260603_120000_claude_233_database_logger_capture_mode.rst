Added
-----

- ``DatabaseLogger.capture_mode`` gates buffer capture independently of
  ``sample_rate`` (which still only governs log output). Three modes:
  ``:all`` (default, unchanged behavior — every command captured),
  ``:sampled`` (capture follows ``sample_rate``), and ``:none`` (capture
  disabled, log-only). In ``:sampled`` and ``:none`` modes a non-sampled
  command now takes a zero-overhead fast path that skips both
  ``Process.clock_gettime`` calls, the ``CommandMessage`` allocation, and the
  buffer append entirely — so ``sample_rate = 0.01`` reduces per-command cost
  to ~1% instead of leaving the 10K-slot buffer churning at full speed.
  Issue #233

- ``Familia.reset_trace!`` clears the cached ``FAMILIA_TRACE`` lookup so the
  next trace check re-reads the environment variable. Mainly useful in tests
  that toggle ``FAMILIA_TRACE`` at runtime. Issue #233

- ``Familia::Instrumentation.hooks?(type)`` reports whether any hooks are
  registered for a category, letting hot paths decide whether collecting
  timing data is worthwhile. Issue #233

Changed
-------

- ``Familia``'s internal ``trace_enabled?`` now caches the ``FAMILIA_TRACE``
  result after first use instead of re-reading ``ENV`` on every trace site,
  removing dozens of environment lookups per request under tracing. Use
  ``Familia.reset_trace!`` to force re-evaluation. Issue #233

- When instrumentation timing is still required (a command or pipeline hook is
  registered), the middleware keeps measuring even for non-sampled,
  non-captured commands, so observability hooks continue to fire at full rate.
  Issue #233

Fixed
-----

- Unguarded ``Familia.trace`` call sites in ``Horreum#destroy!`` and
  ``find_by_dbkey`` now carry an inline ``if Familia.debug?`` guard. Previously
  these built their interpolated message strings (including a full
  ``hash.inspect`` of every loaded record) on every destroy and lookup even
  when debugging was off. Issue #233

AI Assistance
-------------

- AI implemented the ``capture_mode`` gating, the zero-overhead middleware fast
  path across ``call``/``call_pipelined``/``call_once``, the ``trace_enabled?``
  cache, and the trace-site guards. It identified that ``Familia::Instrumentation``
  is always loaded, so the originally proposed ``defined?`` check would have made
  the fast path dead code, and instead gated timing on whether hooks are actually
  registered. Added tryouts coverage for every capture mode (including pipelines,
  instrumentation interaction, and counter behavior) and for the trace cache,
  and verified the existing ``capture_commands`` suite passes unchanged under the
  default ``:all`` mode. Issue #233
