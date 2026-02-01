# frozen_string_literal: true

require 'digest/sha1'

module Familia
  module Migration
    # Lua script registry for atomic Redis operations during migrations.
    #
    # Provides class-level registration and execution of Lua scripts with
    # EVALSHA/EVAL fallback pattern for efficiency. Scripts are precomputed
    # with their SHA1 hashes at registration time.
    #
    # @example Registering a custom script
    #   Familia::Migration::Script.register(:my_script, <<~LUA)
    #     local key = KEYS[1]
    #     return redis.call('GET', key)
    #   LUA
    #
    # @example Executing a script
    #   result = Familia::Migration::Script.execute(
    #     redis,
    #     :rename_field,
    #     keys: ['user:123'],
    #     argv: ['old_name', 'new_name']
    #   )
    #
    class Script
      # Error raised when a script is not found in the registry
      class ScriptNotFound < Familia::Migration::Errors::MigrationError; end

      # Error raised when script execution fails
      class ScriptError < Familia::Migration::Errors::MigrationError; end

      # Holds script source and precomputed SHA1
      ScriptEntry = Data.define(:source, :sha) do
        def initialize(source:, sha: nil)
          computed_sha = sha || Digest::SHA1.hexdigest(source)
          super(source: source.freeze, sha: computed_sha.freeze)
        end
      end

      class << self
        # Access the script registry
        #
        # @return [Hash{Symbol => ScriptEntry}] Frozen hash of registered scripts
        def scripts
          @scripts ||= {}
        end

        # Register a Lua script with the given name
        #
        # @param name [Symbol] Unique identifier for the script
        # @param lua_source [String] The Lua script source code
        # @return [ScriptEntry] The registered script entry
        # @raise [ArgumentError] If name is not a Symbol or source is empty
        def register(name, lua_source)
          raise ArgumentError, 'Script name must be a Symbol' unless name.is_a?(Symbol)
          raise ArgumentError, 'Lua source cannot be empty' if lua_source.nil? || lua_source.strip.empty?

          entry = ScriptEntry.new(source: lua_source.strip)
          scripts[name] = entry
          entry
        end

        # Execute a registered script with EVALSHA/EVAL fallback
        #
        # Attempts EVALSHA first for efficiency. If the script is not cached
        # on the Redis server (NOSCRIPT error), falls back to EVAL which
        # also caches the script for future calls.
        #
        # @param redis [Redis] Redis client connection
        # @param name [Symbol] Name of the registered script
        # @param keys [Array<String>] KEYS array for the Lua script
        # @param argv [Array] ARGV array for the Lua script
        # @return [Object] The script's return value
        # @raise [ScriptNotFound] If the script name is not registered
        # @raise [ScriptError] If script execution fails (other than NOSCRIPT)
        def execute(redis, name, keys: [], argv: [])
          entry = scripts[name]
          raise ScriptNotFound, "Script not found: #{name}" unless entry

          execute_with_fallback(redis, entry, keys, argv, name)
        end

        # Preload all registered scripts to the Redis server
        #
        # Loads scripts using SCRIPT LOAD so subsequent EVALSHA calls
        # will succeed without fallback. Useful at application startup.
        #
        # @param redis [Redis] Redis client connection
        # @return [Hash{Symbol => String}] Map of script names to their SHAs
        def preload_all(redis)
          scripts.each_with_object({}) do |(name, entry), loaded|
            sha = redis.script(:load, entry.source)
            loaded[name] = sha
          end
        end

        # Check if a script is registered
        #
        # @param name [Symbol] Script name to check
        # @return [Boolean] true if the script exists
        def registered?(name)
          scripts.key?(name)
        end

        # Get the SHA for a registered script
        #
        # @param name [Symbol] Script name
        # @return [String, nil] The script's SHA1 hash or nil if not found
        def sha_for(name)
          scripts[name]&.sha
        end

        # Reset the registry (primarily for testing)
        #
        # @return [void]
        def reset!
          @scripts = {}
          register_builtin_scripts
        end

        private

        # Execute script with EVALSHA, falling back to full script on NOSCRIPT
        def execute_with_fallback(redis, entry, keys, argv, name)
          redis.evalsha(entry.sha, keys: keys, argv: argv)
        rescue Redis::CommandError => e
          if e.message.include?('NOSCRIPT')
            # Script not cached on server, send full script (also caches it)
            redis.call('EVAL', entry.source, keys.size, *keys, *argv)
          else
            raise ScriptError, "Script execution failed for #{name}: #{e.message}"
          end
        end

        # Register all built-in migration scripts
        def register_builtin_scripts
          register_rename_field
          register_copy_field
          register_delete_field
          register_rename_key_preserve_ttl
          register_backup_and_modify_field
        end

        def register_rename_field
          register(:rename_field, <<~LUA)
            local key = KEYS[1]
            local old_field = ARGV[1]
            local new_field = ARGV[2]

            if redis.call('HEXISTS', key, new_field) == 1 then
              return redis.error_reply('Target field already exists: ' .. new_field)
            end

            local val = redis.call('HGET', key, old_field)
            if val then
              redis.call('HSET', key, new_field, val)
              redis.call('HDEL', key, old_field)
              return 1
            end
            return 0
          LUA
        end

        def register_copy_field
          register(:copy_field, <<~LUA)
            local key = KEYS[1]
            local src_field = ARGV[1]
            local dst_field = ARGV[2]

            local val = redis.call('HGET', key, src_field)
            if val then
              redis.call('HSET', key, dst_field, val)
              return 1
            end
            return 0
          LUA
        end

        def register_delete_field
          register(:delete_field, <<~LUA)
            local key = KEYS[1]
            local field = ARGV[1]
            return redis.call('HDEL', key, field)
          LUA
        end

        def register_rename_key_preserve_ttl
          register(:rename_key_preserve_ttl, <<~LUA)
            local src = KEYS[1]
            local dst = KEYS[2]

            if redis.call('EXISTS', dst) == 1 then
              return redis.error_reply('Destination key already exists')
            end

            local ttl = redis.call('PTTL', src)
            redis.call('RENAME', src, dst)

            if ttl > 0 then
              redis.call('PEXPIRE', dst, ttl)
            end

            return ttl
          LUA
        end

        def register_backup_and_modify_field
          register(:backup_and_modify_field, <<~LUA)
            local hash_key = KEYS[1]
            local backup_key = KEYS[2]
            local field = ARGV[1]
            local new_value = ARGV[2]
            local ttl = tonumber(ARGV[3])

            local old_val = redis.call('HGET', hash_key, field)
            if old_val then
              redis.call('HSET', backup_key, hash_key .. ':' .. field, old_val)
              if ttl and ttl > 0 then
                redis.call('EXPIRE', backup_key, ttl)
              end
            end
            redis.call('HSET', hash_key, field, new_value)
            return old_val
          LUA
        end
      end

      # Register built-in scripts when the class is loaded
      register_builtin_scripts
    end
  end
end
