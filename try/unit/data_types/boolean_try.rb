# try/unit/data_types/boolean_try.rb
#
# frozen_string_literal: true

# try/data_types/boolean_try.rb
# Issue #190: Updated to reflect JSON serialization with type preservation

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

@hashkey = Familia::HashKey.new 'key'

## String 'true' is stored and returned as string
@hashkey['test'] = 'true'
#=> "true"

## String values are returned as strings
@hashkey['test']
#=> "true"

## Boolean true is now stored with type preservation (Issue #190)
@hashkey['bool_true'] = true
#=> true

## Boolean true is returned as TrueClass
@hashkey['bool_true']
#=> true

## Boolean true has correct class
@hashkey['bool_true'].class
#=> TrueClass

## Boolean false is stored with type preservation
@hashkey['bool_false'] = false
#=> false

## Boolean false is returned as FalseClass
@hashkey['bool_false']
#=> false

## Boolean false has correct class
@hashkey['bool_false'].class
#=> FalseClass

## nil is stored with type preservation
@hashkey['nil_value'] = nil
#=> nil

## nil is returned as nil
@hashkey['nil_value']
#=> nil

## nil has correct class
@hashkey['nil_value'].class
#=> NilClass

## Clear the hash key
@hashkey.delete!
#=> 1
