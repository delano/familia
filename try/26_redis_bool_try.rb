require 'familia'
require 'familia/test_helpers'


@hashkey = Familia::HashKey.new 'key'

@hashkey["test"]="true"
#=> "true"

@hashkey["test"]
#=> "true"

@hashkey["test"]=true
#=> true

@hashkey["test"]
#=> "true"

@hashkey["test"]=nil
#=> nil

@hashkey["test"]
#=> "null"