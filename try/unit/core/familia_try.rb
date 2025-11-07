# try/unit/core/familia_try.rb
#
# frozen_string_literal: true

# try/core/familia_try.rb

require_relative '../../support/helpers/test_helpers'

## Check for help class
Bone.related_fields.keys # consistent b/c hashes are ordered
#=> [:owners, :tags, :metrics, :props, :value, :counter, :lock]

## Familia has a uri
Familia.uri
#=:> URI::Generic

## Familia has a uri as a string
Familia.uri.to_s
#=> 'redis://127.0.0.1:2525'

## Familia has a url, an alias to uri
Familia.url.eql?(Familia.uri)
#=> true
