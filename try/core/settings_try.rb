# try/core/settings_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test Familia configuration and settings management

## Familia has default delim
Familia.delim
#=> ":"

## Can set custom delim
Familia.delim('|')
Familia.delim
#=> "|"

## Familia has default suffix
Familia.suffix
#=> :object

## Can set custom suffix
Familia.suffix(:data)
Familia.suffix
#=> :data

## Familia has default TTL
Familia.ttl
#=> 0

## Can set TTL value
Familia.ttl(3600)
Familia.ttl
#=> 3600.0

## Familia has default database
Familia.db
#=> nil

## Can set database number
Familia.db(2)
Familia.db
#=> 2

## Familia has default prefix
Familia.prefix
#=> nil

## Can set custom prefix
Familia.prefix('app')
Familia.prefix
#=> "app"

## default_suffix method returns suffix
Familia.default_suffix
#=> :data

## Setting values with nil preserves current value
current_ttl = Familia.ttl
Familia.ttl(nil)
Familia.ttl
#=> 3600.0

## Setting delim with nil preserves current value
current_delim = Familia.delim
Familia.delim(nil)
Familia.delim
#=> "|"

# Cleanup - restore defaults
Familia.delim(':')
Familia.suffix(:object)
Familia.ttl(0)
Familia.db(nil)
Familia.prefix(nil)
