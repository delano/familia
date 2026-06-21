# lib/familia/encryption/request_cache.rb
#
# frozen_string_literal: true

# Request-scoped caching for encryption keys (if needed for performance)
# This should ONLY be enabled if performance testing shows it's necessary
#
# SECURITY (see issue #310, S6): the derived-key cache lives in fiber-local
# storage (Fiber[...]). In pooled or async servers a fiber can be reused across
# requests, so the cache MUST be cleared between requests or a key derived by
# one request can leak into a later one. Two safeguards are provided:
#
#   1. #with_request_cache wipes any stale cache on entry AND on exit (ensure),
#      so a reused fiber never starts or finishes a block carrying old keys.
#   2. RequestCacheMiddleware clears the cache at the start of every request and
#      again in an ensure block, so even manual (non-block) usage is bounded to
#      a single request.
#
# Recommended Rack wiring:
#   use Familia::Encryption::RequestCacheMiddleware              # clear-only safety net
#   use Familia::Encryption::RequestCacheMiddleware, enabled: true  # also enable caching

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

    # Rack middleware that bounds the request-scoped derived-key cache to a
    # single request, even when the underlying fiber is reused across requests
    # or the downstream app raises.
    #
    # By default it is a clear-only safety net: it wipes any cache a reused
    # fiber may carry before the request runs, and again afterwards in an
    # ensure block. Pass `enabled: true` to also turn caching on for the
    # duration of each request (via #with_request_cache).
    #
    # @example Clear-only safety net (recommended baseline)
    #   use Familia::Encryption::RequestCacheMiddleware
    #
    # @example Enable per-request caching for performance
    #   use Familia::Encryption::RequestCacheMiddleware, enabled: true
    class RequestCacheMiddleware
      def initialize(app, enabled: false)
        @app = app
        @enabled = enabled
      end

      def call(env)
        if @enabled
          # with_request_cache wipes on entry and exit, so a reused fiber is
          # always isolated to this request.
          Familia::Encryption.with_request_cache { @app.call(env) }
        else
          # Caching stays off (secure default); clear before and after so a
          # reused fiber never carries keys from an adjacent request.
          Familia::Encryption.clear_request_cache!
          begin
            @app.call(env)
          ensure
            Familia::Encryption.clear_request_cache!
          end
        end
      end
    end
  end
end
