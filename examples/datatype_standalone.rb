#!/usr/bin/env ruby
# examples/datatype_standalone.rb

# Demonstration: Familia::StringKey for Session Storage
#
# This example shows how to use Familia's DataType classes independently
# without inheriting from Familia::Horreum. It implements a Rack-compatible
# session store using Familia::StringKey for secure, TTL-managed storage.
#
# Key Familia Features Demonstrated:
# - Standalone DataType usage (no parent model required)
# - TTL management for automatic expiration
# - JSON serialization for complex data structures
# - Direct Redis access through DataType objects
#
# Usage:
#   ruby examples/datatype_standalone.rb
#   # Or in your Rack app:
#   use SecureSessionStore, secret: 'your-secret-key', expire_after: 3600

require 'rack/session/abstract/id'
require 'securerandom'

require 'base64'
require 'openssl'
require 'familia'

module Onetime
  # Onetime::Session - A secure Rack session store using Familia's StringKey DataType
begin
  require 'familia'
rescue LoadError
  # For running from examples directory
  require_relative '../lib/familia'
end
  #
  # This implementation provides secure session storage with HMAC verification
  # and encryption using Familia's Redis-backed StringKey data type.
  #
  # Key Features:
  # - Secure session ID generation with SecureRandom
  # - HMAC-based session integrity verification
  # - JSON serialization for session data
  # - Automatic TTL management via Familia's expiration features
  # - Redis connection pooling via Familia
  #
  # Usage:
  #   use Onetime::Session,
  #     key: 'onetime.session',
  #     secret: ENV.fetch('SESSION_SECRET') { raise "SESSION_SECRET not set" },
  #     expire_after: 3600*24,  # 24 hours
  #     secure: true,  # HTTPS only
  #
  # @see https://raw.githubusercontent.com/rack/rack-session/dadcfe60f193e8/lib/rack/session/abstract/id.rb
  # @see https://raw.githubusercontent.com/rack/rack-session/dadcfe60f193e8/lib/rack/session/encryptor.rb
  class Session < Rack::Session::Abstract::PersistedSecure
    unless defined?(DEFAULT_OPTIONS)
      DEFAULT_OPTIONS = {
        key: 'onetime.session',
        expire_after: 86_400, # 24 hours default
        namespace: 'session',
        sidbits: 256,  # Required by Rack::Session::Abstract::Persisted
        dbclient: nil,
      }.freeze
    end

    attr_reader :dbclient

    def initialize(app, options = {})
      # Require a secret for security
      raise ArgumentError, 'Secret required for secure sessions' unless options[:secret]

      # Merge options with defaults
      options = DEFAULT_OPTIONS.merge(options)

      # Force cookie name to 'onetime.session' for security (custom name prevents
      # session fixation attacks). This overrides Rack's default 'rack.session'.
      # The session key in env['rack.session'] remains standard for compatibility.
      options[:key] = 'onetime.session'

      # Configure Familia connection if redis_uri provided
      @dbclient = options[:dbclient] || Familia.dbclient

      super(app, options)

      @secret = options[:secret]
      @expire_after = options[:expire_after]
      @namespace = options[:namespace] || 'session'

      # Derive different keys for different purposes
      @hmac_key = derive_key('hmac')
      @encryption_key = derive_key('encryption')
    end

    private

    # Create a StringKey instance for a session ID
    def get_stringkey(sid)
      return nil unless sid

      key = Familia.join(@namespace, sid)
      Familia::StringKey.new(key,
        ttl: @expire_after,
        default: nil)
    end

    def delete_session(_request, sid, _options)
      # Extract string ID from SessionId object if needed
      sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

      if stringkey = get_stringkey(sid_string)
        stringkey.del
      end
      generate_sid
    end

    def valid_session_id?(sid)
      return false if sid.to_s.empty?
      return false unless sid.match?(/\A[a-f0-9]{64,}\z/)

      # Additional security checks could go here
      true
    end


    def valid_hmac?(data, hmac)
      expected = compute_hmac(data)
      return false unless hmac.is_a?(String) && expected.is_a?(String) && hmac.bytesize == expected.bytesize
      Rack::Utils.secure_compare(expected, hmac)
    end

    def derive_key(purpose)
      OpenSSL::HMAC.hexdigest('SHA256', @secret, "session-#{purpose}")
    end

    def compute_hmac(data)
      OpenSSL::HMAC.hexdigest('SHA256', @hmac_key, data)
    end

    def find_session(request, sid)
      # Parent class already extracts sid from cookies
      # sid may be a SessionId object or nil
      sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

      # Only generate new sid if none provided or invalid
      unless sid_string && valid_session_id?(sid_string)
        return [generate_sid, {}]
      end

      begin
        stringkey = get_stringkey(sid_string)
        stored_data = stringkey.value if stringkey

        # If no data stored, return empty session
        return [sid, {}] unless stored_data

        # Verify HMAC before deserializing
        data, hmac = stored_data.split('--', 2)

        # If no HMAC or invalid format, create new session
        unless hmac && valid_hmac?(data, hmac)
          # Session tampered with - create new session
          return [generate_sid, {}]
        end

        # Decode and parse the session data
        session_data = Familia::JsonSerializer.parse(Base64.decode64(data))

        [sid, session_data]
      rescue StandardError => e
        # Log error in development/debugging
        Familia.ld "[Session] Error reading session #{sid_string}: #{e.message}"

        # Return new session on any error
        [generate_sid, {}]
      end
    end

    def write_session(_request, sid, session_data, _options)
      # Extract string ID from SessionId object if needed
      sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

      # Serialize and sign the data
      encoded = Base64.encode64(Familia::JsonSerializer.dump(session_data)).delete("\n")
      hmac = compute_hmac(encoded)
      signed_data = "#{encoded}--#{hmac}"

      # Get or create StringKey for this session
      stringkey = get_stringkey(sid_string)

      # Save the session data
      stringkey.set(signed_data)

      # Update expiration if configured
      stringkey.update_expiration(expiration: @expire_after) if @expire_after && @expire_after > 0

      # Return the original sid (may be SessionId object)
      sid
    rescue StandardError => e
      # Log error in development/debugging
      Familia.ld "[Session] Error writing session #{sid_string}: #{e.message}"

      # Return false to indicate failure
      false
    end

    # Clean up expired sessions (optional, can be called periodically)
    def cleanup_expired_sessions
      # This would typically be handled by Redis TTL automatically
      # but you could implement manual cleanup if needed
    end
  end
end

# Demo application showing session store in action
class DemoApp
  def initialize
    @store = SecureSessionStore.new(
      proc { |env| [200, {}, ['Demo App']] },
      secret: 'demo-secret-key-change-in-production',
      expire_after: 300 # 5 minutes for demo
    )
  end

  def call(env)
    puts "\n=== Familia::StringKey Session Demo ==="

    # Mock Rack environment
    env['rack.session'] ||= {}
    env['HTTP_COOKIE'] ||= ''

    # Simulate session operations
    session_id = SecureRandom.hex(32)
    session_data = {
      'user_id' => '12345',
      'username' => 'demo_user',
      'login_time' => Time.now.to_i,
      'preferences' => { 'theme' => 'dark', 'lang' => 'en' }
    }

    puts "📝 Writing session data..."
    result = @store.send(:write_session, nil, session_id, session_data, {})
    puts "   Result: #{result ? 'Success' : 'Failed'}"

    puts "\n📖 Reading session data..."
    found_id, found_data = @store.send(:find_session, nil, session_id)
    puts "   Session ID: #{found_id}"
    puts "   Data: #{found_data}"

    puts "\n🗑️ Deleting session..."
    @store.send(:delete_session, nil, session_id, {})

    puts "\n📖 Verifying deletion..."
    deleted_id, deleted_data = @store.send(:find_session, nil, session_id)
    puts "   Data after deletion: #{deleted_data}"
    puts "   New session ID: #{deleted_id != session_id ? 'Generated' : 'Same'}"

    puts "\n✅ Demo complete!"
    puts "\nKey Familia Features Used:"
    puts "• Familia::StringKey for typed Redis storage"
    puts "• Automatic TTL management"
    puts "• Direct Redis operations (set, get, del)"
    puts "• JSON serialization support"
    puts "• No Horreum inheritance required"

    [200, { 'Content-Type' => 'text/plain' }, ['Familia StringKey Demo - Check console output']]
  end
end

# Run demo if executed directly
if __FILE__ == $0
  # Ensure Redis is available
  begin
    Familia.dbclient.ping
  rescue => e
    puts "❌ Redis connection failed: #{e.message}"
    puts "   Please ensure Redis is running on localhost:6379"
    exit 1
  end

  # Run the demo
  app = DemoApp.new
  app.call({})
end
