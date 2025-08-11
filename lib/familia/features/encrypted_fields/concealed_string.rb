# lib/familia/features/encrypted_fields/concealed_string.rb

# ConcealedString
#
# A secure wrapper for encrypted field values that prevents accidental
# plaintext leakage through serialization, logging, or debugging.
#
# Unlike RedactedString (which wraps plaintext), ConcealedString wraps
# encrypted data and provides controlled decryption through the .reveal API.
#
# Security Model:
#   - Contains encrypted JSON data, never plaintext
#   - Requires explicit .reveal { } for decryption and plaintext access
#   - ALL serialization methods return '[CONCEALED]' to prevent leakage
#   - Maintains encryption context for proper AAD handling
#   - Thread-safe and supports concurrent access
#
# Key Security Features:
#   1. Universal Serialization Safety - ALL to_* methods protected
#   2. Debugging Safety - inspect, logging, console output shows [CONCEALED]
#   3. Exception Safety - never leaks plaintext in error messages
#   4. Future-proof - any new serialization method automatically safe
#   5. Memory Clearing - best-effort encrypted data clearing
#
# Critical Design Principles:
#   - Secure by default - no auto-decryption anywhere
#   - Explicit decryption - .reveal required for plaintext access
#   - Comprehensive protection - covers ALL serialization paths
#   - Auditable access - easy to grep for .reveal usage
#
# Example Usage:
#   user = User.new
#   user.secret_data = "sensitive info"     # Encrypts and wraps
#   user.secret_data                        # Returns ConcealedString
#   user.secret_data.reveal { |plain| ... } # Explicit decryption
#   user.to_h                               # Safe - contains [CONCEALED]
#   user.to_json                            # Safe - contains [CONCEALED]
#
class ConcealedString
  # Create a concealed string wrapper
  #
  # @param encrypted_data [String] The encrypted JSON data
  # @param record [Familia::Horreum] The record instance for context
  # @param field_type [EncryptedFieldType] The field type for decryption
  #
  def initialize(encrypted_data, record, field_type)
    @encrypted_data = encrypted_data.freeze
    @record = record
    @field_type = field_type
    @cleared = false

    # Ensure we don't accidentally store plaintext
    if @encrypted_data && !encrypted_json?(@encrypted_data)
      raise ArgumentError, "ConcealedString requires encrypted JSON data, got: #{@encrypted_data.class}"
    end

    ObjectSpace.define_finalizer(self, self.class.finalizer_proc(@encrypted_data))
  end

  # Primary API: reveal the decrypted plaintext in a controlled block
  #
  # This is the ONLY way to access plaintext from encrypted fields.
  # The plaintext is decrypted fresh each time using the current
  # record state and AAD context.
  #
  # Security Warning: Avoid operations inside the block that create
  # uncontrolled copies of the plaintext (dup, interpolation, etc.)
  #
  # @yield [String] The decrypted plaintext value
  # @return [Object] The return value of the block
  #
  # Example:
  #   user.api_token.reveal do |token|
  #     HTTP.post('/api', headers: { 'X-Token' => token })
  #   end
  #
  def reveal
    raise ArgumentError, 'Block required for reveal' unless block_given?
    raise SecurityError, 'Encrypted data already cleared' if cleared?
    raise SecurityError, 'No encrypted data to reveal' if @encrypted_data.nil?

    # Decrypt using current record context and AAD
    plaintext = @field_type.decrypt_value(@record, @encrypted_data)
    yield plaintext
  end

  # Validate that this ConcealedString belongs to the given record context
  #
  # This prevents cross-context attacks where encrypted data is moved between
  # different records or field contexts. While moving ConcealedString objects
  # manually is not a normal use case, this provides defense in depth.
  #
  # @param expected_record [Familia::Horreum] The record that should own this data
  # @param expected_field_name [Symbol] The field name that should own this data
  # @return [Boolean] true if contexts match, false otherwise
  #
  def belongs_to_context?(expected_record, expected_field_name)
    return false if @record.nil? || @field_type.nil?

    @record.class.name == expected_record.class.name &&
      @record.identifier == expected_record.identifier &&
      @field_type.instance_variable_get(:@name) == expected_field_name
  end


  # Clear the encrypted data from memory
  #
  # Safe to call multiple times. This provides best-effort memory
  # clearing within Ruby's limitations.
  #
  def clear!
    return if @cleared

    @encrypted_data = nil
    @record = nil
    @field_type = nil
    @cleared = true
    freeze
  end

  # Check if the encrypted data has been cleared
  #
  # @return [Boolean] true if cleared, false otherwise
  #
  def cleared?
    @cleared
  end

  # UNIVERSAL SERIALIZATION SAFETY
  #
  # All serialization and inspection methods return '[CONCEALED]'
  # to prevent accidental plaintext leakage through any current
  # or future serialization pathway.
  #

  def to_s
    '[CONCEALED]'
  end

  def inspect
    '[CONCEALED]'
  end

  def to_str
    '[CONCEALED]'
  end

  # JSON serialization safety
  def to_json(*args)
    '"[CONCEALED]"'
  end

  def as_json(*args)
    '[CONCEALED]'
  end

  # Hash/Array serialization safety
  def to_h
    '[CONCEALED]'
  end

  def to_a
    ['[CONCEALED]']
  end

  # String conversion safety
  def to_i
    0
  end

  def to_f
    0.0
  end

  # Prevent accidental equality checks that might leak timing info
  def ==(other)
    object_id.equal?(other.object_id)
  end
  alias eql? ==

  # Consistent hash to prevent timing attacks
  def hash
    ConcealedString.hash
  end

  # Prevent string operations that might leak data
  def +(other)
    '[CONCEALED]'
  end

  def <<(other)
    self
  end

  def concat(other)
    self
  end

  # Pattern matching safety (Ruby 3.0+)
  def deconstruct
    ['[CONCEALED]']
  end

  def deconstruct_keys(keys)
    { concealed: true }
  end

  # Enumeration safety
  def each
    yield '[CONCEALED]' if block_given?
    self
  end

  def map
    yield '[CONCEALED]' if block_given?
    ['[CONCEALED]']
  end

  # Size/length operations
  def size
    11  # Length of '[CONCEALED]'
  end
  alias length size

  def empty?
    false
  end

  def blank?
    false
  end

  def present?
    true
  end

  # Access the encrypted data for database storage
  #
  # This method is used internally by the field type system
  # for persisting the encrypted data to the database.
  #
  # @return [String, nil] The encrypted JSON data
  #
  def encrypted_value
    @encrypted_data
  end

  # String methods that should be safe
  def match(pattern)
    nil
  end

  def match?(pattern)
    false
  end

  def scan(pattern)
    []
  end

  def split(pattern = nil)
    ['[CONCEALED]']
  end

  def gsub(pattern, replacement = nil)
    '[CONCEALED]'
  end

  def gsub!(pattern, replacement = nil)
    self
  end

  def sub(pattern, replacement = nil)
    '[CONCEALED]'
  end

  def sub!(pattern, replacement = nil)
    self
  end

  # Case operations
  def upcase
    '[CONCEALED]'
  end

  def upcase!
    self
  end

  def downcase
    '[CONCEALED]'
  end

  def downcase!
    self
  end

  def capitalize
    '[CONCEALED]'
  end

  def capitalize!
    self
  end

  def swapcase
    '[CONCEALED]'
  end

  def swapcase!
    self
  end

  # Whitespace operations
  def strip
    '[CONCEALED]'
  end

  def strip!
    self
  end

  def lstrip
    '[CONCEALED]'
  end

  def lstrip!
    self
  end

  def rstrip
    '[CONCEALED]'
  end

  def rstrip!
    self
  end

  def chomp(separator = $/)
    '[CONCEALED]'
  end

  def chomp!(separator = $/)
    self
  end

  def chop
    '[CONCEALED]'
  end

  def chop!
    self
  end

  private

  # Check if a string looks like encrypted JSON data
  def encrypted_json?(data)
    return true if data.nil?  # Allow nil values

    begin
      # Encrypted data should be JSON containing algorithm, nonce, etc.
      parsed = JSON.parse(data)
      parsed.is_a?(Hash) && parsed.key?('algorithm')
    rescue JSON::ParserError
      false
    end
  end

  # Finalizer to attempt memory cleanup
  def self.finalizer_proc(encrypted_data)
    proc do |id|
      # Best effort cleanup - Ruby doesn't guarantee memory security
      # Only clear if not frozen to avoid FrozenError
      if encrypted_data&.respond_to?(:clear) && !encrypted_data.frozen?
        encrypted_data.clear
      end
    end
  end
end
