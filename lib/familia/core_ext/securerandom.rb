# lib/familia/core_ext/securerandom.rb
#
# frozen_string_literal: true

require 'securerandom'

# Polyfills for SecureRandom.uuid_v7 and SecureRandom.uuid_v4.
#
# Both named methods were added to Ruby's standard library in Ruby 3.3. Before
# that, only SecureRandom.uuid existed (it produces a v4 UUID). Familia's
# :object_identifier feature offers both :uuid_v7 (the default, for its embedded
# sortable millisecond timestamp) and :uuid_v4 generators, and the gemspec
# supports Ruby >= 3.2, so on Ruby 3.2 we supply faithful fallbacks. On Ruby
# 3.3+ the native methods are present and these blocks are no-ops, leaving the
# stdlib implementations untouched.

# UUIDv4 is exactly what the long-standing SecureRandom.uuid returns, so the
# fallback simply delegates to it.
unless SecureRandom.respond_to?(:uuid_v4)
  def SecureRandom.uuid_v4
    uuid
  end
end

# UUIDv7 layout (RFC 9562, millisecond precision):
#
#   field       bits  description
#   unix_ts_ms   48    Unix timestamp in milliseconds, big-endian
#   ver           4    version, always 0b0111 (7)
#   rand_a       12    random
#   var           2    variant, always 0b10
#   rand_b       62    random
unless SecureRandom.respond_to?(:uuid_v7)
  def SecureRandom.uuid_v7
    unix_ts_ms = Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)

    # 48-bit timestamp split across the first two groups (32 + 16 bits).
    time_hi = (unix_ts_ms >> 16) & 0xffff_ffff
    time_lo = unix_ts_ms & 0xffff

    # Third group: version 7 in the top nibble, then 12 random bits.
    ver_rand_a = 0x7000 | random_number(0x1000)

    # Fourth group: variant 0b10 in the top two bits, then 14 random bits.
    var_rand_b_hi = 0x8000 | random_number(0x4000)

    # Fifth group: the remaining 48 random bits.
    rand_b_lo = random_number(0x1_0000_0000_0000)

    format('%08x-%04x-%04x-%04x-%012x',
           time_hi, time_lo, ver_rand_a, var_rand_b_hi, rand_b_lo)
  end
end
