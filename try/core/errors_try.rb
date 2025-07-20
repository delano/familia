# try/core/errors_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test Familia error classes and exception handling

## Familia::Problem is base error class
Familia::Problem.new.class.superclass
#=> RuntimeError

## NoIdentifier error can be raised
begin
  raise Familia::NoIdentifier, "Missing identifier"
rescue Familia::NoIdentifier => e
  e.class
end
#=> Familia::NoIdentifier

## NonUniqueKey error can be raised
begin
  raise Familia::NonUniqueKey, "Duplicate key"
rescue Familia::NonUniqueKey => e
  e.class
end
#=> Familia::NonUniqueKey

## HighRiskFactor error stores value
begin
  raise Familia::HighRiskFactor.new("dangerous_value")
rescue Familia::HighRiskFactor => e
  e.value
end
#=> "dangerous_value"

## HighRiskFactor error has custom message
begin
  raise Familia::HighRiskFactor.new(123)
rescue Familia::HighRiskFactor => e
  e.message.include?("High risk factor")
end
#=> true

## NotConnected error stores URI
test_uri = URI.parse('redis://localhost:6379')
begin
  raise Familia::NotConnected.new(test_uri)
rescue Familia::NotConnected => e
  e.uri.to_s
end
#=> "redis://localhost"

## NotConnected error has custom message
begin
  raise Familia::NotConnected.new(test_uri)
rescue Familia::NotConnected => e
  e.message.include?("No client for")
end
#=> true

## KeyNotFoundError stores key
begin
  raise Familia::KeyNotFoundError.new("missing:key")
rescue Familia::KeyNotFoundError => e
  e.key
end
#=> "missing:key"

## KeyNotFoundError has custom message
begin
  raise Familia::KeyNotFoundError.new("test:key")
rescue Familia::KeyNotFoundError => e
  e.message.include?("Key not found in Redis")
end
#=> true

## All error classes inherit from Problem
[
  Familia::NoIdentifier,
  Familia::NonUniqueKey,
  Familia::HighRiskFactor,
  Familia::NotConnected,
  Familia::KeyNotFoundError
].all? { |klass| klass.superclass == Familia::Problem }
#=> true
