# try/core/connection_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test connection management and Redis client handling

## Familia has default URI
Familia.uri.class.to_s
#=> "URI::Redis"

## Default URI points to localhost Redis
Familia.uri.to_s
#=> "redis://127.0.0.1"

## Can parse URI from string
uri = URI.parse('redis://localhost:6379/1')
uri.host
#=> "localhost"

## Can establish Redis connection
redis = Familia.connect
redis.class.to_s
#=> "Redis"

## Connection is stored in redis_clients hash
Familia.redis_clients.key?(Familia.uri.serverid)
#=> true

## Can connect to different URI
test_uri = 'redis://localhost:6379/2'
redis2 = Familia.connect(test_uri)
redis2.db
#=> 2

## Redis client responds to basic commands
redis.ping
#=> "PONG"

## Multiple connections are managed separately
Familia.redis_clients.size >= 1
#=> true

## Connection with invalid URI raises error
begin
  Familia.connect(nil)
  false
rescue ArgumentError
  true
end
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

# Cleanup
Familia.enable_redis_logging = false
Familia.enable_redis_counter = false
