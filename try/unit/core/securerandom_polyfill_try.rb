# try/unit/core/securerandom_polyfill_try.rb
#
# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'

# Confirms the SecureRandom.uuid_v7 / uuid_v4 polyfill is wired in ONLY on
# Ruby 3.2. On Ruby 3.3+ the native stdlib implementations must be used and
# our polyfill file (lib/familia/core_ext/securerandom.rb) must not define
# them.
#
# We detect "who defined the method" via Method#source_location:
#   - native stdlib (3.3+): points into ruby's random/formatter.rb
#   - our polyfill (3.2):   points into lib/familia/core_ext/securerandom.rb
# so the method is "polyfilled" exactly when its source file is ours.

Familia.debug = false

POLYFILL_FILE = 'lib/familia/core_ext/securerandom.rb'

def polyfilled?(method_name)
  loc = SecureRandom.method(method_name).source_location
  !loc.nil? && loc.first.end_with?(POLYFILL_FILE)
end

## Both generators are available regardless of Ruby version
[SecureRandom.respond_to?(:uuid_v7), SecureRandom.respond_to?(:uuid_v4)]
#=> [true, true]

## uuid_v7 polyfill is active ONLY on Ruby 3.2 (native on 3.3+)
polyfilled?(:uuid_v7) == (RUBY_VERSION < '3.3')
#=> true

## uuid_v4 polyfill is active ONLY on Ruby 3.2 (native on 3.3+)
polyfilled?(:uuid_v4) == (RUBY_VERSION < '3.3')
#=> true

## Requiring the polyfill directly is a no-op on Ruby 3.3+ (inner RUBY_VERSION guard)
## On 3.2 it (re)defines our fallbacks; either way the source matches the version.
require_relative '../../../lib/familia/core_ext/securerandom'
[polyfilled?(:uuid_v7), polyfilled?(:uuid_v4)].all? { |p| p == (RUBY_VERSION < '3.3') }
#=> true

## uuid_v7 produces a well-formed RFC 9562 v7 UUID (version nibble 7, variant 8-b)
SecureRandom.uuid_v7.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
#=> true

## uuid_v4 produces a well-formed v4 UUID (version nibble 4, variant 8-b)
SecureRandom.uuid_v4.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
#=> true

## uuid_v7 values are time-sortable: a later call sorts lexicographically after an earlier one
@first = SecureRandom.uuid_v7
sleep 0.002
@second = SecureRandom.uuid_v7
@first < @second
#=> true

## successive uuid_v7 calls are unique
SecureRandom.uuid_v7 == SecureRandom.uuid_v7
#=> false
