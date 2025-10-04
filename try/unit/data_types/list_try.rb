# try/data_types/list_try.rb

require_relative '../../support/helpers/test_helpers'

@a = Bone.new 'atoken'

## Familia::ListKey#push
ret = @a.owners.push :value1
ret.class
#=> Familia::ListKey

## Familia::ListKey#<<
ret = @a.owners << :value2 << :value3 << :value4
ret.class
#=> Familia::ListKey

## Familia::ListKey#pop
@a.owners.pop
#=> 'value4'

## Familia::ListKey#first
@a.owners.first
#=> 'value1'

## Familia::ListKey#last
@a.owners.last
#=> 'value3'

## Familia::ListKey#to_a
@a.owners.to_a
#=> ['value1','value2','value3']

## Familia::ListKey#delete
@a.owners.remove 'value3'
#=> 1

## Familia::ListKey#size
@a.owners.size
#=> 2

@a.owners.delete!
