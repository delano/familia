
require_relative '../lib/familia'
require_relative './test_helpers'

## Bug 1: uri= setter correctly handles URI objects
## Previously used undefined variable 'v' instead of 'val'
original_uri = Familia.uri.dup
test_uri = URI.parse('redis://testhost:6380/5')
Familia.uri = test_uri
result = Familia.uri.to_s
Familia.uri = original_uri  # restore
result
#=> 'redis://testhost:6380/5'

## Bug 1: uri= setter correctly handles string URIs
original_uri = Familia.uri.dup
Familia.uri = 'redis://stringhost:6381/7'
result = Familia.uri.to_s
Familia.uri = original_uri  # restore
result
#=> 'redis://stringhost:6381/7'

## Bug 2: redis(db_index) does not mutate global Familia.uri
## Previously tmp = Familia.uri (reference), now tmp = Familia.uri.dup (copy)
Familia.redis(15)  # Request connection to DB 15
Familia.uri.db  # Global URI should be unchanged (default is 0)
#=> 0
