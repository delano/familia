# lib/familia/encryption/request_cache.rb
#
# frozen_string_literal: true

# Request-scoped caching for encryption keys (if needed for performance)
# This should ONLY be enabled if performance testing shows it's necessary
#
# SECURITY (see issue #310, S6): the derived-key cache lives in fiber-local
# storage (Fiber[...]). In pooled or async servers a fiber can be reused across
# requests, so the cache MUST be cleared between requests or a key derived by
# one request can leak into a later one. #with_request_cache therefore wipes any
# stale cache on entry AND on exit (ensure), so a reused fiber never starts or
# finishes a block carrying old keys.
#
# Usage in Rack middleware (clear at the start of every request and again in an
# ensure, so even non-block usage is bounded to a single request):
#
#   class ClearEncryptionCacheMiddleware
#     def initialize(app) = @app = app
#
#     def call(env)
#       Familia::Encryption.clear_request_cache!
#       @app.call(env)
#     ensure
#       Familia::Encryption.clear_request_cache!
#     end
#   end
#
# To also enable caching for the request, wrap the call instead:
#   Familia::Encryption.with_request_cache { @app.call(env) }

module Familia
  module Encryption
    class << self
      # Enable request-scoped caching (opt-in for performance)
      def with_request_cache
        # Wipe any cache a reused fiber may still be carrying before installing a
        # fresh one, so this block can never observe a previous request's keys.
        clear_request_cache!
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
