# try/core/connection_try.rb

require_relative '../helpers/test_helpers'

Familia.debug = false

# Test connection management and Database client handling

## Familia has default URI
Familia.uri
#=:> URI::Generic

## Default URI points to localhost database server
Familia.uri.to_s
#=> "redis://127.0.0.1"

## Can parse URI from string
uri = URI.parse('redis://localhost:2525/1')
uri.host
#=> "localhost"

## Can establish Database connection
Familia.create_dbclient
#=:> Redis

## Can establish Database connection with deprecated method
Familia.connect
#=:> Redis

## Can create connection to different URI
## Doesn't confirm the logical DB number, dbclient.options raises an error?
test_uri = 'redis://localhost:2525/2'
Familia.create_dbclient(test_uri)
#=:> Redis

## Database client responds to basic commands
Familia.dbclient.ping
#=> "PONG"

## Can enable Database logging
Familia.enable_database_logging = true
Familia.enable_database_logging
#=> true

## Can enable Database command counter
Familia.enable_database_counter = true
Familia.enable_database_counter
#=> true

## Middleware gets registered when enabled
dbclient = Familia.create_dbclient('redis://localhost:2525/3')
dbclient.ping
#=> "PONG"

## Cleanup
Familia.enable_database_logging = false
Familia.enable_database_counter = false
