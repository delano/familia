# try/unit/core/errors_try.rb
#
# frozen_string_literal: true

# try/core/errors_try.rb

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Test Familia error classes and exception handling

## Familia::Problem is base error class
Familia::Problem.new.class.superclass
#=> RuntimeError

## NoIdentifier error can be raised
begin
  raise Familia::NoIdentifier, 'Missing identifier'
rescue Familia::NoIdentifier => e
  e.class
end
#=> Familia::NoIdentifier

## NonUniqueKey error can be raised
begin
  raise Familia::NonUniqueKey, 'Duplicate key'
rescue Familia::NonUniqueKey => e
  e.class
end
#=> Familia::NonUniqueKey

## NotDistinguishableError error stores value
begin
  raise Familia::NotDistinguishableError.new('dangerous_value')
rescue Familia::NotDistinguishableError => e
  e.value
end
#=> "dangerous_value"

## NotDistinguishableError error has custom message
raise Familia::NotDistinguishableError, 'A customized message'
#=:> Familia::NotDistinguishableError
#=~> /A customized message/

## NotConnected error stores URI
test_uri = URI.parse('redis://localhost:2525')
begin
  raise Familia::NotConnected.new(test_uri)
rescue Familia::NotConnected => e
  e.uri.to_s
end
#=> "redis://localhost:2525"

## NotConnected error has custom message
test_uri = URI.parse('redis://localhost:2525')
begin
  raise Familia::NotConnected.new(test_uri)
rescue Familia::NotConnected => e
  e.message.include?('No client for')
end
#=> true

## KeyNotFoundError stores key
begin
  raise Familia::KeyNotFoundError.new('missing:key')
rescue Familia::KeyNotFoundError => e
  e.key
end
#=> "missing:key"

## KeyNotFoundError has custom message
begin
  raise Familia::KeyNotFoundError.new('test:key')
rescue Familia::KeyNotFoundError => e
  e.message.include?('Key not found')
end
#=> true

## KeyNotFoundError has custom message again
raise Familia::KeyNotFoundError.new('test:key')
#=!> error.message.include?("Key not found")
#=!> error.class == Familia::KeyNotFoundError

## RecordExistsError stores key
begin
  raise Familia::RecordExistsError.new('existing:key')
rescue Familia::RecordExistsError => e
  e.key
end
#=> "existing:key"

## RecordExistsError has custom message
begin
  raise Familia::RecordExistsError.new('existing:key')
rescue Familia::RecordExistsError => e
  e.message.include?('Key already exists')
end
#=> true

## RecordExistsError inherits from NonUniqueKey
Familia::RecordExistsError.superclass
#=> Familia::NonUniqueKey

## RecordExistsError.existing_id defaults to nil when not provided
Familia::RecordExistsError.new('my_key').existing_id
#=> nil

## RecordExistsError.existing_id is exposed when provided as kwarg
Familia::RecordExistsError.new('my_key', existing_id: 'abc123').existing_id
#=> "abc123"

## RecordExistsError message format when existing_id is nil
Familia::RecordExistsError.new('my_key').message
#=> "Key already exists: my_key"

## RecordExistsError message format when existing_id is set
Familia::RecordExistsError.new('my_key', existing_id: 'abc123').message
#=> "Key already exists: my_key (existing_id=abc123)"

## Legacy call style (single positional arg via raise) still works - existing_id is nil
begin
  raise Familia::RecordExistsError, 'legacy:key'
rescue Familia::RecordExistsError => e
  [e.existing_id, e.message]
end
#=> [nil, "Key already exists: legacy:key"]

## RecordExistsError#message is idempotent across repeated calls
err = Familia::RecordExistsError.new('my_key', existing_id: 'abc123')
[err.message, err.message, err.message].uniq
#=> ["Key already exists: my_key (existing_id=abc123)"]

## All error classes inherit from Problem
[
  Familia::NoIdentifier,
  Familia::NonUniqueKey,
  Familia::NotDistinguishableError,
  Familia::NotConnected,
  Familia::KeyNotFoundError,
  Familia::RecordExistsError
].all? { |klass| klass.superclass == Familia::Problem || klass.superclass.superclass == Familia::Problem }
##=> true
