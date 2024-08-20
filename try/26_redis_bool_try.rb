require_relative '../lib/familia'
require_relative './test_helpers'

Familia.debug = false

@hashkey = Familia::HashKey.new 'key'


## Boolean values are returned as strings, on assignment as string
@hashkey["test"] = "true"
#=> "true"

## Boolean values are returned as strings
@hashkey["test"]
#=> "true"

## Trying to store a boolean value to a hash key raises an exception
begin
  @hashkey["test"] = true
rescue Familia::HighRiskFactor => e
  e.message
end
#=> "High risk factor for serialization bugs: true<TrueClass>"

## Boolean values are returned as strings
@hashkey["test"]
#=> "true"

## Trying to store a nil value to a hash key raises an exception
begin
  @hashkey["test"] = nil
rescue Familia::HighRiskFactor => e
  e.message
end
#=> "High risk factor for serialization bugs: <NilClass>"

## The exceptions prevented the hash from being updated
@hashkey["test"]
#=> "true"

## Clear the hash key
@hashkey.clear
#=> 1
