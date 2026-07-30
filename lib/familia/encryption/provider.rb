# lib/familia/encryption/provider.rb
#
# frozen_string_literal: true

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

      # Derived-key length in bytes. Read lazily rather than in initialize so
      # provider subclasses written before KEY_SIZE existed still construct;
      # they raise a NameError naming the missing constant only when asked.
      def key_size
        self.class::KEY_SIZE
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

      # Clear key from memory (best effort, no security guarantees)
      # Ruby provides no reliable way to securely wipe memory
      def secure_wipe(key)
        key&.clear if key.respond_to?(:clear)
      end

      # Check if this provider is available
      def self.available?
        raise NotImplementedError
      end

      # Priority for automatic selection (higher = preferred)
      def self.priority
        0
      end

      # Human-readable name of the runtime dependency this provider needs to be
      # `available?`, or nil when it has none (e.g. an always-available OpenSSL
      # provider). Used only to build a helpful error when a field is pinned to a
      # known algorithm whose provider isn't installed on this node; override in
      # subclasses whose availability is gated on an optional library.
      def self.dependency_hint
        nil
      end
    end
  end
end
