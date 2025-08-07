# lib/familia/features/transient_fields/redacted_string.rb

# RedactedString
#
# Meant to securely clear the string from memory.
class RedactedString
  def initialize(value)
    @value = value.to_s.dup
    # Freeze to discourage mutation
    @value.freeze
  end

  def to_s
    '[REDACTED]'
  end

  def inspect
    '[REDACTED]'
  end

  def clear!
    if defined?(RbNaCl)
      RbNaCl::Util.zero(@value)
    else
      @value.replace('x' * @value.length) # Best-effort overwrite
      @value.freeze
    end
  end
end
