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
# ⚠️ INPUT SECURITY: The constructor calls .dup on the input, creating a copy,
#                   but the original input value remains in memory uncontrolled.
#                   The caller is responsible for securely clearing the original.
#
# Security Model:
#   - The secret is *contained* from the moment it's wrapped.
#   - Access is available via `.expose { }` for controlled use, or `.value` for direct access.
#   - Manual `.clear!` is required when done with the value (unlike SingleUseRedactedString).
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
#   - Clear original input after wrapping: `secret.clear!` or `secret = nil`
#   - Use `.expose { }` for short-lived operations — never store plaintext.
#   - Avoid passing RedactedString to logging, serialization, or debugging
#     tools.
#   - Prefer `.expose { }` over any "getter" method.
#   - Do *not* subclass String — it leaks the underlying value in regex,
#     case, etc.
#
# Example:
#   password_input = params[:password]     # Original value in memory
#   password = RedactedString.new(password_input)
#   password_input.clear! if password_input.respond_to?(:clear!)
#   # or: params[:password] = nil          # Clear reference (not guaranteed)
#
class RedactedString
  # Wrap a sensitive value. The input is *not* wiped — ensure it's not reused.
  def initialize(original_value)
    # WARNING: .dup only creates a shallow copy; the original may still exist
    # elsewhere in memory.
    @value = original_value.to_s.dup
    @cleared = false
    # Do NOT freeze — we need to mutate it in `#clear!`
    ObjectSpace.define_finalizer(self, self.class.finalizer_proc)
  end

  # Primary API: expose the value in a block.
  # The value remains accessible for multiple reads until manually cleared.
  # Call clear! explicitly when done with the value.
  #
  # ⚠️ Security Warning: Avoid .dup, string interpolation, or other operations
  #    that create uncontrolled copies of the sensitive value.
  #
  # Example:
  #   token.expose do |plain|
  #     # Good: use directly without copying
  #     HTTP.post('/api', headers: { 'X-Token' => plain })
  #     # Avoid: plain.dup, "prefix#{plain}", plain[0..-1], etc.
  #   end
  #   # Value is still accessible after block
  #   token.clear! # Explicitly clear when done
  #
  def expose
    raise ArgumentError, 'Block required' unless block_given?
    raise SecurityError, 'Value already cleared' if cleared?

    yield @value
  end

  # Clear the internal buffer. Safe to call multiple times.
  #
  # REALITY CHECK: This doesn't actually provide security in Ruby.
  # - Ruby may have already copied the string elsewhere in memory
  # - Garbage collection behavior is unpredictable
  # - The original input value is still in memory somewhere
  # - This is primarily for API consistency and preventing reuse
  def clear!
    return if @value.nil? || @value.frozen? || @cleared

    # Simple clear - no security theater
    @value.clear if @value.respond_to?(:clear)
    @value = nil
    @cleared = true
    freeze # one and done
  end

  # Get the actual value (for convenience in less sensitive contexts)
  # Returns the wrapped value or nil if cleared
  #
  # ⚠️ Security Warning: Direct access bypasses the controlled exposure pattern.
  #    Prefer .expose { } for better security practices.
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
