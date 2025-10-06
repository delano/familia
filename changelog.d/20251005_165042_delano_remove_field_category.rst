.. Connection Pool Middleware Refresh

Added
-----

- Added ``Familia.reconnect!`` method to refresh connection pools with current middleware configuration. This solves issues in test suites where middleware (like DatabaseLogger) is enabled after connection pools are created. The method clears the connection chain, increments the middleware version, and clears fiber-local connections, ensuring new connections include the latest middleware. See ``lib/familia/connection/middleware.rb:81-117``.

Fixed
-----

- Fixed middleware registration to only set ``@middleware_registered`` flag when middleware is actually enabled and registered. Previously, calling ``create_dbclient`` before enabling middleware would set the flag to ``true`` without registering anything, preventing later middleware enablement from working. The fix ensures ``register_middleware_once`` only sets the flag after successful registration. See ``lib/familia/connection/middleware.rb:124-146``.

AI Assistance
-------------

- Claude Code (Sonnet 4.5) provided architecture analysis, implementation design, and identified critical issues through the second-opinion agent. Key contributions included recommending the simplified approach without pool shutdown lifecycle management, identifying the race condition risk in clearing ``@middleware_registered``, and suggesting the use of natural pool aging instead of explicit shutdown.
