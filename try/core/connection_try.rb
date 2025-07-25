# try/core/connection_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test connection management and Redis client handling

## Familia has default URI
Familia.uri
#=:> URI::Redis

## Default URI points to localhost Redis
Familia.uri.to_s
#=> "redis://127.0.0.1"

## Can parse URI from string
uri = URI.parse('redis://localhost:6379/1')
uri.host
#=> "localhost"

## Can establish Redis connection
Familia.connect
#=:> Redis

## Can connect to different URI
## Doesn't confirm the logical DB number, redis.options raises an error?
test_uri = 'redis://localhost:6379/2'
Familia.connect(test_uri)
#=:> Redis

## Redis client responds to basic commands
Familia.redis.ping
#=> "PONG"

## Multiple connections are managed separately
Familia.redis_clients.size >= 1
#=> true

## Can enable Redis logging
Familia.enable_redis_logging = true
Familia.enable_redis_logging
#=> true

## Can enable Redis command counter
Familia.enable_redis_counter = true
Familia.enable_redis_counter
#=> true

## Middleware gets registered when enabled
redis3 = Familia.connect('redis://localhost:6379/3')
redis3.ping
#=> "PONG"

## Cleanup
Familia.enable_redis_logging = false
Familia.enable_redis_counter = false
