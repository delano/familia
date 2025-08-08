# lib/familia/encryption/provider.rb

module Familia
  module Encryption
    # Base provider class - similar to FieldType pattern
    class Provider
      attr_reader :algorithm, :nonce_size, :auth_tag_size

      def initialize
        @algorithm = self.class::ALGORITHM
        @nonce_size = self.class::NONCE_SIZE
        @auth_tag_size = self.class::AUTH_TAG_SIZE
      end

      # Public interface methods that subclasses must implement
      def encrypt(plaintext, key, additional_data = nil)
        raise NotImplementedError
      end

      def decrypt(ciphertext, key, nonce, auth_tag, additional_data = nil)
        raise NotImplementedError
      end

      def generate_nonce
        raise NotImplementedError
      end

      def derive_key(master_key, context)
        raise NotImplementedError
      end

      def secure_wipe(key)
        raise NotImplementedError
      end

      # Check if this provider is available
      def self.available?
        raise NotImplementedError
      end

      # Priority for automatic selection (higher = preferred)
      def self.priority
        0
      end
    end
  end
end
