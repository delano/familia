
require_relative '../lib/familia'
require_relative './test_helpers'

#Familia.apiversion = 'v1'


## Check for help class
Bone.redis_types.keys # consistent b/c hashes are ordered
#=> [:owners, :tags, :metrics, :props, :value]

## Familia has a uri
Familia.uri.class
#=> URI::Redis

## Familia has a uri as a string
Familia.uri.to_s
#=> 'redis://127.0.0.1'

## Familia has a url, an alias to uri
Familia.url.eql?(Familia.uri)
#=> true
