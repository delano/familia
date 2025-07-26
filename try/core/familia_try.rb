# try/core/familia_try.rb


require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

#Familia.apiversion = 'v1'


## Check for help class
Bone.related_fields.keys # consistent b/c hashes are ordered
#=> [:owners, :tags, :metrics, :props, :value]

## Familia has a uri
Familia.uri
#=:> URI::Generic

## Familia has a uri as a string
Familia.uri.to_s
#=> 'redis://127.0.0.1'

## Familia has a url, an alias to uri
Familia.url.eql?(Familia.uri)
#=> true
