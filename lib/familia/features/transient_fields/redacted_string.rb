# lib/familia/features/transient_fields/redacted_string.rb

# RedactedString
#
# A secure wrapper for sensitive string values (e.g., API keys, passwords,
# encryption keys).
# Designed to:
#   - Prevent accidental logging/inspection
#   - Enable secure memory wiping
#   - Encourage safe usage patterns
#
# ⚠️ IMPORTANT: This is *best-effort* protection. Ruby does not guarantee
#              memory zeroing. GC, string sharing, and internal optimizations
#              may leave copies in memory.
#
# Security Model:
#   - The secret is *contained* from the moment it's wrapped.
#   - Access is only allowed via `.expose { }`, which ensures cleanup.
#   - `.to_s` and `.inspect` return '[REDACTED]' to prevent leaks in logs,
#     errors, or debugging.
#
# Critical Gotchas:
#
# 1. Ruby 3.4+ String Internals — Memory Safety Reality
#    - Ruby uses "compact strings" and copy-on-write semantics.
#    - Short strings (< 24 bytes on 64-bit) are *embedded* in the object
#      (RSTRING_EMBED_LEN).
#    - Long strings use heap-allocated buffers, but may be shared or
#      duplicated silently.
#    - There is *no guarantee* that GC will not copy the string before
#      finalization.
#
# 2. Every .dup, .to_s, +, interpolation, or method call may create hidden
#    copies:
#      s = "secret"
#      t = s.dup        # New object, same content — now two copies
#      u = s + "123"    # New string — third copy
#      "#{t}"           # Interpolation — fourth copy
#    These copies are *not* controlled by RedactedString and may persist.
#
# 3. String Freezing & Immutability
#    - `.freeze` prevents mutation but does *not* prevent copying.
#    - `.replace` on a frozen string raises FrozenError — so wiping fails.
#
# 4. RbNaCl::Util.zero Limitations
#    - Only works on mutable byte buffers.
#    - May not zero embedded strings if Ruby's internal representation is
#      immutable.
#    - Does *not* protect against memory dumps or GC-compacted heaps.
#
# 5. Finalizers Are Not Guaranteed
#    - Ruby does not promise when (or if) `ObjectSpace.define_finalizer`
#      runs.
#    - Never rely on finalizers for security-critical wiping.
#
# Best Practices:
#   - Wrap secrets *immediately* on input (e.g., from ENV, params, DB).
#   - Use `.expose { }` for short-lived operations — never store plaintext.
#   - Avoid passing RedactedString to logging, serialization, or debugging
#     tools.
#   - Prefer `.expose { }` over any "getter" method.
#   - Do *not* subclass String — it leaks the underlying value in regex,
#     case, etc.
#
class RedactedString
  # Wrap a sensitive value. The input is *not* wiped — ensure it's not reused.
  def initialize(original_value)
    @value = original_value.to_s.dup # force a copy
    @cleared = false
    # Do NOT freeze — we need to mutate it in `#clear!`
    ObjectSpace.define_finalizer(self, self.class.finalizer_proc)
  end

  # Primary API: expose the value in a block.
  # The value remains accessible for multiple reads.
  # Call clear! explicitly when done with the value.
  #
  # Example:
  #   token.expose do |plain|
  #     HTTP.post('/api', headers: { 'X-Token' => plain })
  #   end
  #   # Value is still accessible after block
  #   token.clear! # Explicitly clear when done
  #
  def expose
    raise ArgumentError, 'Block required' unless block_given?
    raise SecurityError, 'Value already cleared' if cleared?

    yield @value
  end

  # Wipe the internal buffer. Safe to call multiple times.
  # Uses RbNaCl::Util.zero if available (preferred).
  # Falls back to overwriting with 'X' pattern.
  def clear!
    return if @value.nil? || @value.frozen? || @cleared

    if defined?(RbNaCl)
      RbNaCl::Util.zero(@value)
    elsif @value.length.positive?
      # Best-effort: overwrite with junk
      @value.replace("\x00" * @value.length)
    end

    @value = nil
    @cleared = true
    freeze # one and done
  end

  # Get the actual value (for convenience in less sensitive contexts)
  # Returns the wrapped value or nil if cleared
  def value
    raise SecurityError, 'Value already cleared' if cleared?

    @value
  end

  # Always redact in logs, debugging, or string conversion
  def to_s = '[REDACTED]'
  def inspect = to_s
  def cleared? = @cleared

  # Returns true when it's literally the same object, otherwsie false.
  # This prevents timing attacks where an attacker could potentially
  # infer information about the secret value through comparison timing
  def ==(other)
    object_id.equal?(other.object_id) # same object
  end
  alias eql? ==

  # All RedactedString instances have the same hash to prevent
  # hash-based timing attacks or information leakage
  def hash
    RedactedString.hash
  end

  def self.finalizer_proc = proc { |id| }
end
