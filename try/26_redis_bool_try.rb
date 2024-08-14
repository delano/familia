require_relative '../lib/familia'
require_relative './test_helpers'

Familia.debug = true

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
rescue TypeError => e
  e.message
end
#=> "Cannot store test => true (TrueClass) in key"

## Boolean values are returned as strings
@hashkey["test"]
#=> "true"

## Trying to store a nil value to a hash key raises an exception
begin
  @hashkey["test"] = nil
rescue TypeError => e
  e.message
end
#=> "Cannot store test => nil (NilClass) in key"

## The exceptions prevented the hash from being updated
@hashkey["test"]
#=> "true"
