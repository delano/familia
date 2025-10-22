# try/unit/core/middleware_debug_try.rb
#
# Debug: Let's check middleware state during reconnect

require_relative '../../../lib/familia'

# Enable counter
Familia.enable_database_counter = true
Familia.uri = 'redis://127.0.0.1:2525'

## Middleware is registered after enabling counter
Familia.instance_variable_get(:@middleware_registered)
#=> true

## Middleware version is 1
Familia.middleware_version
#=> 1

# Call reconnect!
Familia.reconnect!

## After reconnect: middleware_registered is true again
Familia.instance_variable_get(:@middleware_registered)
#=> true

## After reconnect: version incremented
Familia.middleware_version
#=> 2

# Now enable logging
Familia.enable_database_logging = true

## After enabling logging: middleware_registered stays true
Familia.instance_variable_get(:@middleware_registered)
#=> true

## After enabling logging: version incremented again
Familia.middleware_version
#=> 3

# Get a connection and inspect it
dbclient = Familia.dbclient

## Connection is a Redis instance
dbclient.class.name
#=> "Redis"

# Check if the underlying RedisClient has middleware
# The Redis gem wraps RedisClient, so we need to dig into it
redis_client = dbclient._client

## RedisClient instance exists
redis_client.class.name
#=> "RedisClient"

# Check the middleware list
middlewares = redis_client.instance_variable_get(:@middlewares)

## Middlewares are registered (should be an array)
middlewares.nil?
#=> false

## Number of middlewares registered
middlewares&.size || 0
#=> 2
