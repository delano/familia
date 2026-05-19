# lib/familia/encryption/request_cache.rb
#
# frozen_string_literal: true

# Request-scoped caching for encryption keys (if needed for performance)
# This should ONLY be enabled if performance testing shows it's necessary
#
# Usage in Rack middleware:
#   class ClearEncryptionCacheMiddleware
#     def call(env)
#       Familia::Encryption.clear_request_cache!
#       @app.call(env)
#     ensure
#       Familia::Encryption.clear_request_cache!
#     end
#   end

module Familia
  module Encryption
    class << self
      # Enable request-scoped caching (opt-in for performance)
      def with_request_cache
        Fiber[:familia_request_cache_enabled] = true
        Fiber[:familia_request_cache] = {}
        yield
      ensure
        clear_request_cache!
      end

      # Clear all cached keys and disable caching
      def clear_request_cache!
        if (cache = Fiber[:familia_request_cache])
          cache.each_value { |key| secure_wipe(key) }
          cache.clear
        end
        Fiber[:familia_request_cache_enabled] = false
        Fiber[:familia_request_cache] = nil
      end

      # NOTE: The actual cache lookup lives in
      # Familia::Encryption::Manager#derive_key_without_increment, which is the
      # single key-derivation path for both encrypt and decrypt. This module
      # only owns the opt-in lifecycle (enable, populate-by-Manager, wipe).
    end
  end
end
