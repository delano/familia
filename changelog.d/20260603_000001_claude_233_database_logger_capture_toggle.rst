Added
-----

- ``DatabaseLogger.capture_enabled`` (Boolean, default ``true``) controls whether
  Redis commands are captured into the in-memory buffer, independently of
  ``sample_rate`` (which still governs only log output). With capture enabled,
  behaviour is unchanged. With it disabled, a command that is also not sampled
  for logging and has no registered instrumentation hook takes a zero-overhead
  fast path that skips both ``clock_gettime`` calls, the ``CommandMessage``
  allocation, and the buffer append. This makes ``capture_enabled = false`` the
  production setting: keep sampled logs, drop the per-command buffer/timing cost.
  Issue #233

- ``Familia::Instrumentation.hooks?(type)`` predicate reports whether any hooks
  are registered for a given event type (``:command``, ``:pipeline``,
  ``:lifecycle``, ``:error``). Because the module is always loaded, a
  ``defined?`` check could not gate the new fast path; the middleware uses this
  predicate so observability hooks keep firing at full rate (timing is still
  measured) even when command capture is off. Issue #233

- ``Familia.reset_trace!`` clears the cached ``FAMILIA_TRACE`` lookup so the next
  trace check re-reads the environment (primarily for tests that mutate the
  variable). Issue #233

Changed
-------

- ``trace_enabled?`` now caches the ``FAMILIA_TRACE`` lookup instead of reading
  the environment on every call, removing dozens of redundant ``ENV`` reads per
  request under tracing. Use ``Familia.reset_trace!`` to force a re-read.
  Issue #233

Fixed
-----

- The unguarded ``Familia.trace`` sites in ``Horreum#destroy!`` and
  ``find_by_dbkey`` now carry an inline ``if Familia.debug?`` guard. Previously
  their message strings -- including a full ``hash.inspect`` of every loaded
  record in ``find_by_dbkey`` -- were built unconditionally even with debugging
  off. Issue #233

AI Assistance
-------------

- AI implemented the ``capture_enabled`` toggle and fast-path short-circuit
  across ``call``/``call_pipelined``/``call_once``, ensuring ``should_log?`` is
  still evaluated exactly once per command so deterministic sampling is
  preserved, and that the formatted log path keeps working when capture is off.
  Added the ``hooks?`` predicate, the ``trace_enabled?`` cache with
  ``reset_trace!``, and the trace-site guards, plus tryouts covering
  ``capture_enabled = false`` (no capture, logging still sampled, fast path),
  instrumentation forcing the measured path, and ``trace_enabled?`` caching.
