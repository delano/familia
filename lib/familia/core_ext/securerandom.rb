# lib/familia/core_ext/securerandom.rb
#
# frozen_string_literal: true

require 'securerandom'

# Polyfills for SecureRandom.uuid_v7 and SecureRandom.uuid_v4 -- Ruby 3.2 only.
#
# Both named methods entered Ruby's standard library in Ruby 3.3. Ruby 3.2 is
# the oldest version familia supports (the gemspec's required_ruby_version
# floor), and there only SecureRandom.uuid exists (it produces a v4 UUID).
# Familia's :object_identifier feature offers both :uuid_v7 (the default, for
# its embedded sortable millisecond timestamp) and :uuid_v4 generators, so on
# Ruby 3.2 we supply faithful fallbacks.
#
# The RUBY_VERSION guard below ensures these definitions exist ONLY on Ruby
# 3.2: on Ruby 3.3+ the block is skipped entirely and the native stdlib
# implementations are left untouched. The caller (lib/familia/secure_identifier.rb)
# also gates the require on RUBY_VERSION, so on 3.3+ this file is normally never
# loaded -- the guard here is a second line of defence in case it is required
# directly.
if RUBY_VERSION < '3.3'
  # UUIDv4 is exactly what the long-standing SecureRandom.uuid returns, so the
  # fallback simply delegates to it.
  def SecureRandom.uuid_v4
    uuid
  end

  # UUIDv7 layout (RFC 9562, millisecond precision):
  #
  #   field       bits  description
  #   unix_ts_ms   48    Unix timestamp in milliseconds, big-endian
  #   ver           4    version, always 0b0111 (7)
  #   rand_a       12    random
  #   var           2    variant, always 0b10
  #   rand_b       62    random
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
