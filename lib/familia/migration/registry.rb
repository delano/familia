# lib/familia/migration/registry.rb — Redis-backed state tracking
#
# frozen_string_literal: true

require 'json'
require 'digest'

module Familia
  module Migration
    # Registry provides Redis-backed tracking for migration state.
    #
    # Storage Schema (Redis keys):
    #   {prefix}:applied   - Sorted Set (member=migration_id, score=timestamp)
    #   {prefix}:metadata  - Hash (field=migration_id, value=JSON metadata)
    #   {prefix}:schema    - Hash (field=model_name, value=schema_digest)
    #   {prefix}:backup:{id} - Hash with TTL for rollback data
    #
    # @example Basic usage
    #   registry = Familia::Migration::Registry.new
    #   registry.applied?('20260131_add_status_field')  # => false
    #   registry.record_applied(migration, stats)
    #   registry.applied?('20260131_add_status_field')  # => true
    #
    class Registry
      # @return [Redis, nil] The Redis client for this registry
      attr_reader :redis

      # @return [String] The key prefix for all registry data
      attr_reader :prefix

      # Initialize a new Registry instance.
      #
      # @param redis [Redis, nil] Redis client (defaults to Familia.dbclient)
      # @param prefix [String, nil] Key prefix (defaults to config.migrations_key)
      #
      def initialize(redis: nil, prefix: nil)
        @redis = redis
        @prefix = prefix || Familia::Migration.config.migrations_key
      end

      # Get the Redis client: the one passed to #initialize, or else
      # Familia.dbclient resolved on each call.
      #
      # The fallback is not memoized. Familia.dbclient returns the open
      # transaction or pipeline connection inside those blocks, and a
      # memoized one would keep queueing commands on it after the block
      # completed. Each registry method resolves the client once and issues
      # all of its commands on it, so a method opens at most one connection
      # when Familia.dbclient creates a new one per call.
      #
      # @return [Redis] The Redis client
      #
      def client
        @redis || Familia.dbclient
      end

      # --- Query Methods ---

      # Check if a migration has been applied.
      #
      # @param migration_id [String] The migration identifier
      # @return [Boolean, Redis::Future] true if the migration is in the
      #   applied set. On a transaction or pipeline connection, the ZSCORE Future.
      #
      def applied?(migration_id)
        Familia.transform_reply(client.zscore(applied_key, migration_id.to_s)) { |score| !score.nil? }
      end

      # Get the timestamp when a migration was applied.
      #
      # @param migration_id [String] The migration identifier
      # @return [Time, nil, Redis::Future] The time the migration was applied,
      #   or nil if not applied. On a transaction or pipeline connection, the
      #   ZSCORE Future.
      #
      def applied_at(migration_id)
        Familia.transform_reply(client.zscore(applied_key, migration_id.to_s)) do |score|
          score.nil? ? nil : Time.at(score)
        end
      end

      # Get all applied migrations with their timestamps.
      #
      # @return [Array<Hash>, Redis::Future] Array of hashes with :migration_id
      #   and :applied_at keys. On a transaction or pipeline connection, the
      #   ZRANGE Future.
      #
      def all_applied
        applied_entries(client)
      end

      # Filter a list of migrations to only those not yet applied.
      #
      # @param all_migrations [Array<Class>] All migration classes
      # @return [Array<Class>] Migration classes that haven't been applied
      #
      def pending(all_migrations)
        return [] if all_migrations.nil? || all_migrations.empty?

        conn = client
        assert_replies_available!(:pending, conn)

        # Batch fetch all applied migration IDs in a single Redis call
        applied_ids = conn.zrange(applied_key, 0, -1).to_set

        all_migrations.reject do |migration|
          migration_id = extract_migration_id(migration)
          applied_ids.include?(migration_id)
        end
      end

      # Get metadata for a specific migration.
      #
      # @param migration_id [String] The migration identifier
      # @return [Hash, nil, Redis::Future] Parsed JSON metadata or nil if not
      #   found. On a transaction or pipeline connection, the HGET Future.
      #
      def metadata(migration_id)
        read_metadata(client, migration_id)
      end

      # Get the status of all migrations.
      #
      # @param all_migrations [Array<Class>] All migration classes
      # @return [Array<Hash>] Array of status hashes with :migration_id, :status, :applied_at
      #
      def status(all_migrations)
        return [] if all_migrations.nil? || all_migrations.empty?

        conn = client
        assert_replies_available!(:status, conn)

        # Batch fetch all applied migrations with timestamps in a single Redis call
        applied_info = applied_entries(conn).each_with_object({}) do |entry, hash|
          hash[entry[:migration_id]] = entry[:applied_at]
        end

        all_migrations.map do |migration|
          migration_id = extract_migration_id(migration)
          timestamp = applied_info[migration_id]

          {
            migration_id: migration_id,
            status: timestamp ? :applied : :pending,
            applied_at: timestamp,
          }
        end
      end

      # --- Recording Methods ---

      # Record that a migration has been applied.
      #
      # @param migration [Class, Object] The migration class or instance
      # @param stats [Hash] Statistics from the migration run
      # @option stats [Float] :duration_ms Duration in milliseconds
      # @option stats [Integer] :keys_scanned Number of keys scanned
      # @option stats [Integer] :keys_modified Number of keys modified
      # @option stats [Integer] :errors Number of errors
      # @option stats [Boolean] :reversible Whether the migration is reversible
      #
      def record_applied(migration, stats = {})
        migration_id = extract_migration_id(migration)
        now = Time.now
        conn = client

        # ZADD to applied set with current timestamp
        conn.zadd(applied_key, now.to_f, migration_id)

        # Build metadata
        meta = {
          status: 'applied',
          applied_at: now.iso8601,
          duration_ms: stats[:duration_ms] || 0,
          keys_scanned: stats[:keys_scanned] || 0,
          keys_modified: stats[:keys_modified] || 0,
          errors: stats[:errors] || 0,
          reversible: stats[:reversible] || false,
        }

        # HSET metadata JSON
        conn.hset(metadata_key, migration_id, JSON.generate(meta))
      end

      # Record that a migration has been rolled back.
      #
      # @param migration_id [String] The migration identifier
      #
      def record_rollback(migration_id)
        conn = client
        assert_replies_available!(:record_rollback, conn)
        migration_id = migration_id.to_s

        # Remove from applied set
        conn.zrem(applied_key, migration_id)

        # Update metadata to show rolled_back status
        existing = read_metadata(conn, migration_id)
        meta = existing || {}
        meta[:status] = 'rolled_back'
        meta[:rolled_back_at] = Time.now.iso8601

        conn.hset(metadata_key, migration_id, JSON.generate(meta))
      end

      # --- Schema Tracking Methods ---

      # Calculate the schema digest for a model class.
      #
      # @param model_class [Class] A Familia::Horreum subclass
      # @return [String] SHA256 hex digest of the field schema
      #
      def schema_digest(model_class)
        fields = model_class.fields.sort
        field_types = model_class.field_types

        field_strings = fields.map do |field|
          type = field_types[field] || 'unknown'
          "#{field}:#{type}"
        end

        Digest::SHA256.hexdigest(field_strings.join('|'))
      end

      # Store the current schema digest for a model class.
      #
      # @param model_class [Class] A Familia::Horreum subclass
      #
      def store_schema(model_class)
        model_name = model_class.name || model_class.to_s
        digest = schema_digest(model_class)
        client.hset(schema_key, model_name, digest)
      end

      # Get the stored schema digest for a model class.
      #
      # @param model_class [Class] A Familia::Horreum subclass
      # @return [String, nil, Redis::Future] The stored digest or nil if not
      #   found. On a transaction or pipeline connection, the HGET Future.
      #
      def stored_schema(model_class)
        read_stored_schema(client, model_class)
      end

      # Check if the schema has changed for a model class.
      #
      # @param model_class [Class] A Familia::Horreum subclass
      # @return [Boolean] true if schema differs from stored version
      #
      def schema_changed?(model_class)
        conn = client
        assert_replies_available!(:schema_changed?, conn)
        stored = read_stored_schema(conn, model_class)
        return false if stored.nil? # No stored schema = no drift

        stored != schema_digest(model_class)
      end

      # Get a list of model classes with changed schemas.
      #
      # @return [Array<String>] Model names with schema drift
      #
      def schema_drift
        conn = client
        assert_replies_available!(:schema_drift, conn)
        # Get all stored schemas
        stored = conn.hgetall(schema_key)
        return [] if stored.empty?

        drifted = []

        stored.each do |model_name, stored_digest|
          # Try to find the model class
          model_class = find_model_class(model_name)
          next if model_class.nil?

          current_digest = schema_digest(model_class)
          drifted << model_name if stored_digest != current_digest
        end

        drifted
      end

      # --- Backup Methods ---

      # Store a backup of a field value for potential rollback.
      #
      # @param migration_id [String] The migration identifier
      # @param key [String] The Redis key being modified
      # @param field [String] The field name within the key
      # @param value [String] The original value to preserve
      #
      def backup_field(migration_id, key, field, value)
        bkey = backup_key(migration_id)
        conn = client
        conn.hset(bkey, "#{key}:#{field}", value)
        conn.expire(bkey, Familia::Migration.config.backup_ttl)
      end

      # Restore all backed up fields for a migration.
      #
      # @param migration_id [String] The migration identifier
      # @return [Integer] Number of fields restored
      #
      def restore_backup(migration_id)
        conn = client
        assert_replies_available!(:restore_backup, conn)
        bkey = backup_key(migration_id)
        backup_data = conn.hgetall(bkey)
        return 0 if backup_data.empty?

        count = 0

        backup_data.each do |composite_key, value|
          # Parse "redis_key:field_name" format
          # Note: field_name might contain colons, so we only split on the last colon
          parts = composite_key.rpartition(':')
          redis_key = parts[0]
          field_name = parts[2]

          next if redis_key.empty? || field_name.empty?

          conn.hset(redis_key, field_name, value)
          count += 1
        end

        count
      end

      # Clear the backup data for a migration.
      #
      # @param migration_id [String] The migration identifier
      #
      def clear_backup(migration_id)
        client.del(backup_key(migration_id))
      end

      private

      # Refuses an operation that must read a reply before it can finish when
      # the client queues commands (a transaction or pipeline connection,
      # given explicitly or resolved by Familia.dbclient inside such a
      # block). Every reply there is a Redis::Future until the block
      # completes. Checks the client rather than the fiber context because a
      # registry built with its own client is unaffected by an open block.
      #
      # @param operation [Symbol] the method name for the error message
      # @param conn [Redis, Redis::PipelinedConnection] the client the
      #   operation will issue its commands on
      # @raise [Familia::OperationModeError]
      def assert_replies_available!(operation, conn)
        Familia.assert_replies_available!("Migration::Registry##{operation}", conn: conn)
      end

      # Applied migrations with their timestamps, read on +conn+.
      #
      # @param conn [Redis, Redis::PipelinedConnection]
      # @return [Array<Hash>, Redis::Future] the ZRANGE Future on a
      #   transaction or pipeline connection
      def applied_entries(conn)
        # redis-rb pairs the ZRANGE WITHSCORES reply as [[member, score], ...]
        # with Float scores.
        results = conn.zrange(applied_key, 0, -1, withscores: true)

        Familia.transform_reply(results) do |pairs|
          pairs.map do |migration_id, score|
            {
              migration_id: migration_id,
              applied_at: Time.at(score),
            }
          end
        end
      end

      # Parsed metadata for +migration_id+, read on +conn+.
      #
      # @param conn [Redis, Redis::PipelinedConnection]
      # @return [Hash, nil, Redis::Future] the HGET Future on a transaction
      #   or pipeline connection
      def read_metadata(conn, migration_id)
        Familia.transform_reply(conn.hget(metadata_key, migration_id.to_s)) do |json|
          json.nil? ? nil : JSON.parse(json, symbolize_names: true)
        end
      end

      # Stored schema digest for +model_class+, read on +conn+.
      #
      # @param conn [Redis, Redis::PipelinedConnection]
      # @return [String, nil, Redis::Future]
      def read_stored_schema(conn, model_class)
        conn.hget(schema_key, model_class.name || model_class.to_s)
      end

      # --- Key Helpers ---

      def applied_key
        "#{@prefix}:applied"
      end

      def metadata_key
        "#{@prefix}:metadata"
      end

      def schema_key
        "#{@prefix}:schema"
      end

      def backup_key(migration_id)
        "#{@prefix}:backup:#{migration_id}"
      end

      # --- Utility Methods ---

      # Extract migration ID from various input types.
      #
      # @param migration [Class, Object, String] Migration class, instance, or ID
      # @return [String] The migration identifier
      #
      def extract_migration_id(migration)
        case migration
        when String
          migration
        when Class
          migration.respond_to?(:migration_id) ? migration.migration_id : migration.name
        else
          migration.class.respond_to?(:migration_id) ? migration.class.migration_id : migration.class.name
        end.to_s
      end

      # Find a model class by name from Familia's registry.
      #
      # @param model_name [String] The class name
      # @return [Class, nil] The model class or nil
      #
      def find_model_class(model_name)
        Familia.members.find { |m| m.name == model_name }
      end
    end
  end
end
