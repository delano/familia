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
Familia.default_expiration
#=> 0

## Can set default expiration value
Familia.default_expiration(3600)
Familia.default_expiration
#=> 3600.0

## Familia has default database
Familia.logical_database
#=> nil

## Can set database number
Familia.logical_database(2)
Familia.logical_database
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
current_default_expiration = Familia.default_expiration
Familia.default_expiration(nil)
Familia.default_expiration
#=> 3600.0

## Setting delim with nil preserves current value
current_delim = Familia.delim
Familia.delim(nil)
Familia.delim
#=> "|"

# Cleanup - restore defaults
Familia.delim(':')
Familia.suffix(:object)
Familia.default_expiration(0)
Familia.logical_database(nil)
Familia.prefix(nil)
