# try/horreum/base_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

@identifier = 'tryouts-27@onetimesecret.com'
@customer = Customer.new @identifier
@hashkey = Familia::HashKey.new 'tryouts-27'

## Customer passed as value is returned as string identifier, on assignment as string
## TODO: Revisit these @identifier testcases b/c I think we don't want to be setting
## the @identifier instance var anymore since identifer_field should only take field
## names now (and might be removed altogether).
@hashkey['test1'] = @customer.identifier
#=> @identifier

## Customer passed as value is returned as string identifier
@hashkey['test1']
#=> @identifier

## Trying to store a customer to a hash key implicitly converts it to string identifier
## we can't tell from the return value this way either. Here the store method return value
## is either 1 (if the key is new) or 0 (if the key already exists).
@hashkey.store 'test2', @customer
#=> 1

## Trying to store a customer to a hash key implicitly converts it to string identifier
## but we can't tell that from the return value. Here the hash syntax return value
## is the value that is being assigned.
@hashkey['test2'] = @customer
#=> @customer

## Trying store again with the same key returns 0
@hashkey.store 'test2', @customer
#=> 0

## Customer passed as value is returned as string identifier
@hashkey['test2']
#=> @identifier

## Remove the key
@hashkey.delete!
#=> true

## Horreum objects can update and save their fields (1 of 2)
@customer.name = 'John Doe'
#=> "John Doe"

## Horreum objects can update and save their fields (2 of 2)
@customer.save
#=> true

## Horreum object fields have a fast attribute method (1 of 2)
Familia.trace :LOAD, @customer.dbclient, @customer.uri, caller if Familia.debug?
@customer.name! 'Jane Doe'
#=> 0

## Horreum object fields have a fast attribute method (2 of 2)
@customer.refresh!
@customer.name
#=> "Jane Doe"

## Unsaved changes are lost when an object reloads
@customer.name = 'John Doe'
@customer.refresh!
@customer.name
#=> "Jane Doe"

## Horreum objects can be destroyed
@customer.destroy!
#=> true

## All horrerum objects have a key field
@customer.identifier
#=> @identifier

## Even ones that didn't define it
class NoIdentifierClass < Familia::Horreum
  field :name
end
@no_id = NoIdentifierClass.new name: 'test'
@no_id.identifier
#=> nil

## We can call #identifier directly if we want to "lasy load" the unique identifier
@cd = CustomDomain.new display_domain: 'www.example.com', custid: 'domain-test@example.com'
@cd.identifier
#=:> String
#=/=> _.empty?
#==> _.size > 16
#=~>/\A[0-9a-z]+\z/

## The identifier is now memoized (same value each time)
@cd_first_call = @cd.identifier
@cd_second_call = @cd.identifier
@cd_first_call == @cd_second_call
#=> true

## But once we save
@cd.save
#=> true

## The key has been set now that the instance has been saved
@cd.identifier
#=:> String
#=/=> _.empty?
#==> _.size > 16
#=~>/\A[0-9a-z]+\z/

## Array-based identifiers are no longer supported and raise clear errors at class definition time
class ArrayIdentifierTest < Familia::Horreum
  identifier_field %i[token name] # This should raise an error immediately
  field :token
  field :name
end
#=!> Familia::Problem

## Redefining a field method after it was defined gives a warning
class FieldRedefine < Familia::Horreum
  identifier_field :email
  field :name
  field :uniquefieldname

  def uniquefieldname
    true
  end
end
#=> :uniquefieldname
#=2> /WARNING/
#=2> /uniquefieldname/

## Defining a field with the same name as an existing method raises an exception
class FieldRedefine < Familia::Horreum
  identifier_field :email
  field :name

  def uniquefieldname
    true
  end

  field :uniquefieldname
end
#=!> ArgumentError

## Field aliasing works with 'as' parameter
class AliasedFieldTest < Familia::Horreum
  identifier_field :email
  field :email
  field :display_size, as: :width
end
@aliased = AliasedFieldTest.new email: 'test@example.com'
@aliased.width = 42
@aliased.width
#=> 42

## Aliased field getter method uses alias name
@aliased.respond_to?(:width)
#=> true

## Aliased field setter method uses alias name
@aliased.respond_to?(:width=)
#=> true

## Original field name is not accessible as method
@aliased.respond_to?(:display_size)
#=> false

## Aliased field fast method works correctly
@aliased.save
@aliased.display_size! 100
#=> 1

## Aliased field refresh works correctly
@aliased.width = 50  # unsaved change
@aliased.refresh!
@aliased.width
#=> 100

## Fast method with custom name
class CustomFastMethodTest < Familia::Horreum
  identifier_field :email
  field :score, fast_method: :score_now!
  field :email
end
@custom_fast = CustomFastMethodTest.new email: 'fast@example.com'
@custom_fast.respond_to?(:score_now!)
#=> true

## Custom fast method works
@custom_fast.save
@custom_fast.score_now! 75
#=> 0

## Field with :warn conflict handling allows redefinition with warning
class WarnConflictTest < Familia::Horreum
  identifier_field :email
  field :email
  field :test_method, on_conflict: :warn

  def test_method
    "original"
  end

end
@warn_test = WarnConflictTest.new email: 'warn@example.com'
@warn_test.test_method
#=> "original"

## Field with :skip conflict handling skips redefinition silently
class SkipConflictTest < Familia::Horreum
  identifier_field :email
  field :email

  def skip_method
    "original"
  end

  field :skip_method, on_conflict: :skip
end
@skip_test = SkipConflictTest.new email: 'skip@example.com'
@skip_test.skip_method
#=> "original"

## Combined aliasing and custom fast method
class CombinedTest < Familia::Horreum
  identifier_field :email
  field :internal_count, as: :count, fast_method: :count_immediately!
  field :email
end
@combined = CombinedTest.new email: 'combined1@example.com'
@combined.count = 10
@combined.count
#=> 10

## Combined test fast method works
@combined.save
@combined.count_immediately! 20
@combined.count
#=> 20

## Combined test refresh works
combined = CombinedTest.new email: 'combined2@example.com'
combined.count = 5  # unsaved change
combined.refresh!
combined.count
#=> 5
