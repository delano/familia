Changed
-------

- **Structured Logging**: Replaced internal logging methods (``Familia.ld``, ``Familia.le``) with structured logging methods (``Familia.debug``, ``Familia.info``, ``Familia.error``) that support keyword context for operational observability.

Added
-----

- **Instrumentation Hooks**: New ``Familia::Instrumentation`` module provides hooks for Redis commands, pipeline operations, lifecycle events, and errors. Applications can now register callbacks for audit trails and performance monitoring.

- **DatabaseLogger Structured Mode**: Added ``DatabaseLogger.structured_logging`` mode that outputs Redis commands with structured key=value context instead of formatted string output.

- **DatabaseLogger Sampling**: Added ``DatabaseLogger.sample_rate`` for controlling log volume in high-traffic scenarios. Set to 0.1 for 10% sampling, 0.01 for 1% sampling, or nil to disable. Command capture for testing remains unaffected.

- **Lifecycle Logging**: Horreum initialize, save, and destroy operations now log with timing and structured context when ``FAMILIA_DEBUG`` is enabled.

- **Operational Logging**: TTL operations and serialization errors now include structured context for better debugging.

Removed
-------

- **Internal Methods**: Removed ``Familia.ld`` and ``Familia.le`` internal logging methods. These were never part of the public API.

Developer Notes
---------------

This is a clean break for v2.0 with no deprecation warnings, as the removed methods were internal-only. Applications using the public API are unaffected.

**Migration**: No action required for external users. Internal development references to ``Familia.ld`` should use ``Familia.debug``, and ``Familia.le`` should use ``Familia.error``.

**New Capabilities**: Applications can now register instrumentation hooks for operational observability:

.. code-block:: ruby

   # Enable structured logging with 10% sampling for production
   Familia.logger = Rails.logger
   DatabaseLogger.structured_logging = true
   DatabaseLogger.sample_rate = 0.1  # Log 10% of commands

   # Register hooks for audit trails
   Familia.on_command do |cmd, duration_ms, context|
     AuditLog.create!(
       event: 'redis_command',
       command: cmd,
       duration_ms: duration_ms,
       user_id: RequestContext.current_user_id
     )
   end

   Familia.on_lifecycle do |event, instance, context|
     case event
     when :save
       AuditLog.create!(event: 'object_saved', object_id: instance.identifier)
     when :destroy
       AuditLog.create!(event: 'object_destroyed', object_id: instance.identifier)
     end
   end

AI Assistance
-------------

This implementation was completed with significant AI assistance from Claude (Anthropic), including:

- Architecture design for the instrumentation hook system
- Implementation of structured logging methods with backward-compatible signatures
- Integration of hooks into DatabaseLogger middleware
- Bulk replacement of 51 logging method calls across 21 files
- Comprehensive code review and bug fixes (RedisClient::Config object vs hash handling)
- Documentation and changelog creation

The AI provided discussion, rubber ducking, code generation, testing strategy, and documentation throughout the implementation process.
