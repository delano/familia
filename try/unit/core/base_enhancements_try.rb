# try/unit/core/base_enhancements_try.rb
#
# frozen_string_literal: true

# try/core/base_enhancements_try.rb

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Base class provides default UUID generation
class BaseUuidTest < Familia::Horreum
  identifier_field :id
  field :id
end

# Empty class still has base functionality
class EmptyBaseTest < Familia::Horreum
end

@base_uuid = BaseUuidTest.new(id: 'uuid_test_1')

## UUID generation creates unique identifiers
@uuid1 = @base_uuid.uuid
@uuid1
#=:> String

## UUID is properly formatted
@uuid1
#=~>/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

## UUID is memoized (same value on repeated calls)
@uuid2 = @base_uuid.uuid
@uuid1 == @uuid2
#=> true

## Different instances get different UUIDs
@base_uuid2 = BaseUuidTest.new(id: 'uuid_test_2')
@base_uuid.uuid != @base_uuid2.uuid
#=> true

## Base class provides ID generation
@generated_id1 = @base_uuid.generate_id
@generated_id1
#=:> String

## Generated ID is memoized
@generated_id2 = @base_uuid.generate_id
@generated_id1 == @generated_id2
#=> true

## Base class to_s method returns identifier
@base_uuid.to_s
#=> "uuid_test_1"

## Feature registry is accessible
Familia::Base.features_available
#=:> Hash

## Feature definitions registry is accessible
Familia::Base.feature_definitions
#=:> Hash

## Base class includes proper modules
BaseUuidTest.ancestors.include?(Familia::Base)
#=> true

## Feature methods are accessible through the class
BaseUuidTest.respond_to?(:feature)
#=> true

## Class instance variables are properly initialized
BaseUuidTest.instance_variable_get(:@fields)
#=:> Array

## Field definitions are properly initialized
BaseUuidTest.instance_variable_get(:@field_types)
#=:> Hash

## Feature system is properly integrated
BaseUuidTest.respond_to?(:feature)
#=> true

## Feature registration methods are available
Familia::Base.respond_to?(:add_feature)
#=> true

## Valid identifiers work correctly
@base_uuid.identifier
#=> "uuid_test_1"

## Empty class has base methods available
EmptyBaseTest.ancestors.include?(Familia::Base)
#=> true

## Empty class can use feature system
EmptyBaseTest.respond_to?(:feature)
#=> true

## Test Base module constants are defined
Familia::Base.features_available
#=:> Hash

## Base module provides inspect with class name
@base_uuid.inspect.include?('BaseUuidTest')
#=> true

@base_uuid.destroy! rescue nil
@base_uuid2.destroy! rescue nil
@base_uuid = nil
@base_uuid2 = nil
