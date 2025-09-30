# try/data_types/boolean_try.rb

require_relative '../helpers/test_helpers'

Familia.debug = false

@hashkey = Familia::HashKey.new 'key'

## Boolean values are returned as strings, on assignment as string
@hashkey['test'] = 'true'
#=> "true"

## Boolean values are returned as strings
@hashkey['test']
#=> "true"

## Trying to store a boolean value to a hash key raises an exception
begin
  @hashkey['test'] = true
rescue Familia::NotDistinguishableError => e
  e.message
end
#=> "Cannot represent true<TrueClass> as a string"

## Boolean values are returned as strings
@hashkey['test']
#=> "true"

## Trying to store a nil value to a hash key raises an exception
begin
  @hashkey['test'] = nil
rescue Familia::NotDistinguishableError => e
  e.message
end
#=> "Cannot represent <NilClass> as a string"

## The exceptions prevented the hash from being updated
@hashkey['test']
#=> "true"

## Clear the hash key
@hashkey.delete!
#=> true
