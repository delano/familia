# lib/familia/encryption/request_cache.rb
#
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

      private

      # Modified derive_key that uses request cache when enabled
      def derive_key_with_optional_cache(context, version: nil)
        version ||= current_key_version
        master_key = get_master_key(version)

        # Only use cache if explicitly enabled for this request
        if Fiber[:familia_request_cache_enabled]
          cache = Fiber[:familia_request_cache] ||= {}
          cache_key = "#{version}:#{context}"

          # Return cached key if available (within same request only)
          if (cached = cache[cache_key])
            return cached.dup
          end

          # Derive and cache for this request only
          derived = perform_key_derivation(master_key, context)
          cache[cache_key] = derived.dup
          derived
        else
          # Default: no caching for maximum security
          perform_key_derivation(master_key, context)
        end
      ensure
        secure_wipe(master_key) if master_key
      end
    end
  end
end
