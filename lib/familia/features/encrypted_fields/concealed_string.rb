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
  REDACTED = '[CONCEALED]'.freeze

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

    # Parse and validate the encrypted data structure
    if @encrypted_data
      begin
        @encrypted_data_obj = Familia::Encryption::EncryptedData.from_json(@encrypted_data)
        # Validate that the encrypted data is decryptable (algorithm supported, etc.)
        @encrypted_data_obj.validate_decryptable!
      rescue Familia::EncryptionError => e
        raise Familia::EncryptionError, e.message
      rescue StandardError => e
        raise Familia::EncryptionError, "Invalid encrypted data: #{e.message}"
      end
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

    @record.instance_of?(expected_record.class) &&
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

  def empty?
    @encrypted_data.to_s.empty?
  end

  # Returns true when it's literally the same object, otherwise false.
  # This prevents timing attacks where an attacker could potentially
  # infer information about the secret value through comparison timing
  def ==(other)
    object_id.equal?(other.object_id) # same object
  end
  alias eql? ==

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

  # Prevent accidental exposure through string conversion and serialization
  #
  # Ruby has two string conversion methods with different purposes:
  # - to_s: explicit conversion (`obj.to_s`, string interpolation `"#{obj}"`)
  # - to_str: implicit coercion (`File.read(obj)`, `"prefix" + obj`)
  #
  # We implement to_s for safe logging/debugging but deliberately omit to_str
  # to prevent encrypted data from being used where strings are expected.
  #
  def to_s
    '[CONCEALED]'
  end

  # String methods that should return safe concealed values
  def upcase
    '[CONCEALED]'
  end

  def downcase
    '[CONCEALED]'
  end

  def length
    11 # Fixed concealed length to match '[CONCEALED]' length
  end

  def size
    length
  end

  def present?
    true # Always return true since encrypted data exists
  end

  def blank?
    false # Never blank if encrypted data exists
  end

  # String concatenation operations return concealed result
  def +(_other)
    '[CONCEALED]'
  end

  def concat(_other)
    '[CONCEALED]'
  end

  # Handle coercion for concatenation like "string" + concealed
  def coerce(other)
    if other.is_a?(String)
      ['[CONCEALED]', '[CONCEALED]']
    else
      [other, '[CONCEALED]']
    end
  end

  # String pattern matching methods
  def strip
    '[CONCEALED]'
  end

  def gsub(*)
    '[CONCEALED]'
  end

  def include?(_substring)
    false # Never reveal substring presence
  end

  # Enumerable methods for safety
  def map
    yield '[CONCEALED]' if block_given?
    ['[CONCEALED]']
  end

  def each
    yield '[CONCEALED]' if block_given?
    self
  end

  # Safe representation for debugging and console output
  def inspect
    '[CONCEALED]'
  end

  # Hash/Array serialization safety
  def to_h
    '[CONCEALED]'
  end

  def to_a
    ['[CONCEALED]']
  end

  # Consistent hash to prevent timing attacks
  def hash
    ConcealedString.hash
  end

  # Pattern matching safety (Ruby 3.0+)
  def deconstruct
    ['[CONCEALED]']
  end

  def deconstruct_keys(*)
    { concealed: true }
  end

  # Prevent exposure in JSON serialization - fail closed for security
  def to_json(*)
    raise Familia::SerializerError, 'ConcealedString cannot be serialized to JSON'
  end

  # Prevent exposure in Rails serialization (as_json -> to_json)
  def as_json(*)
    '[CONCEALED]'
  end

  # Finalizer to attempt memory cleanup
  def self.finalizer_proc(encrypted_data)
    proc do
      # Best effort cleanup - Ruby doesn't guarantee memory security
      # Only clear if not frozen to avoid FrozenError
      encrypted_data.clear if encrypted_data.respond_to?(:clear) && !encrypted_data.frozen?
    end
  end

  private

  # Check if a string looks like encrypted JSON data
  def encrypted_json?(data)
    Familia::Encryption::EncryptedData.valid?(data)
  end
end
