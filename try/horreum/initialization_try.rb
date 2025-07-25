# try/horreum/initialization_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

## Existing positional argument initialization still works
@customer1 = Customer.new 'tryouts-29@test.com', '', '', '', '', 'John Doe'
[@customer1.custid, @customer1.name]
#=> ["tryouts-29@test.com", "John Doe"]

## Keyword argument initialization works (order independent)
@customer2 = Customer.new(name: 'Jane Smith', custid: 'jane@test.com', email: 'jane@example.com')
[@customer2.custid, @customer2.name, @customer2.email]
#=> ["jane@test.com", "Jane Smith", "jane@example.com"]

## Keyword arguments are order independent (different order, same result)
@customer3 = Customer.new(email: 'bob@example.com', custid: 'bob@test.com', name: 'Bob Jones')
[@customer3.custid, @customer3.name, @customer3.email]
#=> ["bob@test.com", "Bob Jones", "bob@example.com"]

## Legacy hash support (single hash argument)
@customer4 = Customer.new({custid: 'legacy@test.com', name: 'Legacy User', role: 'admin'})
[@customer4.custid, @customer4.name, @customer4.role]
#=> ["legacy@test.com", "Legacy User", "admin"]

## Empty initialization works
@customer5 = Customer.new
@customer5.class
#=> Customer

## Keyword args with save and retrieval
@customer6 = Customer.new(custid: 'save-test@test.com', name: 'Save Test', email: 'save@example.com')
@customer6.save
#=> true

## Saved customer can be retrieved with correct values
@customer6.refresh!
[@customer6.custid, @customer6.name, @customer6.email]
#=> ["save-test@test.com", "Save Test", "save@example.com"]

## Keyword initialization sets key field correctly
@customer6.key
#=> "save-test@test.com"

## Mixed valid and nil values in keyword args (nil values stay nil)
@customer7 = Customer.new(custid: 'mixed@test.com', name: 'Mixed Test', email: nil, role: 'user')
[@customer7.custid, @customer7.name, @customer7.email, @customer7.role]
#=> ["mixed@test.com", "Mixed Test", nil, "user"]

## to_h works correctly with keyword-initialized objects
@customer2.to_h[:name]
#=> "Jane Smith"

## to_a works correctly with keyword-initialized objects
@customer2.to_a[5]  # name field should be at index 5
#=> "Jane Smith"

## Session has limited fields (only sessid defined)
@session1 = Session.new('sess123')
@session1.sessid
#=> "sess123"

## Session with keyword args works
@session2 = Session.new(sessid: 'keyword-sess')
@session2.sessid
#=> "keyword-sess"

## Session with legacy hash
@session3 = Session.new({sessid: 'hash-sess'})
@session3.sessid
#=> "hash-sess"

## CustomDomain with keyword initialization
@domain1 = CustomDomain.new(display_domain: 'api.example.com', custid: 'domain-test@test.com')
[@domain1.display_domain, @domain1.custid]
#=> ["api.example.com", "domain-test@test.com"]

## CustomDomain still works with positional args
@domain2 = CustomDomain.new('web.example.com', 'positional@test.com')
[@domain2.display_domain, @domain2.custid]
#=> ["web.example.com", "positional@test.com"]

## Keyword initialization can skip fields (they remain nil/empty)
@partial = Customer.new(custid: 'partial@test.com', name: 'Partial User')
[@partial.custid, @partial.name, @partial.email]
#=> ["partial@test.com", "Partial User", nil]

## Complex initialization with save/refresh cycle
@complex = Customer.new(
  custid: 'complex@test.com',
  name: 'Complex User',
  email: 'complex@example.com',
  role: 'admin',
  verified: true
)
@complex.save
@complex.refresh!
[@complex.custid, @complex.name, @complex.role, @complex.verified]
#=> ["complex@test.com", "Complex User", "admin", "true"]

## Clean up saved test objects
[@customer6, @complex].map(&:delete!)
#=> [true, true]

## "Cleaning up" test objects that were never saved returns false.
@customer1.save
ret = [
  @customer1, @customer2, @customer3, @customer4, @customer6, @customer7,
  @session1, @session2, @session3,
  @domain1, @domain2,
  @partial, @complex
].map(&:destroy!)
#=> [true, false, false, false, false, false, false, false, false, false, false, false, false]
