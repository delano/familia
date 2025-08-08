# lib/familia/features/transient_fields/single_use_redacted_string.rb

require_relative 'redacted_string'

# SingleUseRedactedString
#
# A high-security variant of RedactedString that automatically clears
# its value after a single use via the expose method. Unlike RedactedString,
# this provides automatic cleanup and enforces single-use semantics.
#
# ⚠️ IMPORTANT: Inherits all security limitations from RedactedString regarding
#              Ruby's memory management and copy-on-write semantics.
#
# ⚠️ INPUT SECURITY: Like RedactedString, the constructor calls .dup on input,
#                   creating a copy, but the original input remains in memory.
#                   The caller is responsible for securely clearing the original.
#
# Key Differences from RedactedString:
#   - Automatically clears after expose() (no manual clear! needed)
#   - Blocks direct value() access (prevents accidental multi-use)
#   - Raises SecurityError on second expose() attempt
#
# Use this for extremely sensitive values that should only be accessed
# once, such as:
#   - One-time passwords (OTPs)
#   - Temporary authentication tokens
#   - Encryption keys that should be immediately discarded
#
# Example:
#   otp_input = params[:otp]               # Original value in memory
#   otp = SingleUseRedactedString.new(otp_input)
#   params[:otp] = nil                     # Clear reference (not guaranteed)
#   otp.expose do |code|
#     verify_otp(code)                     # Use directly without copying
#   end
#   # Value is automatically cleared after block
#   otp.cleared? #=> true
#
class SingleUseRedactedString < RedactedString
  # Override expose to automatically clear after use
  #
  # This ensures the value can only be accessed once via expose,
  # providing maximum security for single-use secrets.
  #
  def expose
    raise ArgumentError, 'Block required' unless block_given?
    raise SecurityError, 'Value already cleared' if cleared?

    yield @value
  ensure
    clear! # Automatically clear after single use
  end

  # Override value accessor to prevent direct access
  #
  # For single-use secrets, we don't want to allow direct value access
  # to maintain the single-use guarantee.
  #
  def value
    raise SecurityError, 'Direct value access not allowed for single-use secrets. Use #expose with a block.'
  end
end
