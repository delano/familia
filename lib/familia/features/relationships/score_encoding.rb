# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      # Score encoding module for embedding metadata in Redis sorted set scores
      #
      # Scores are encoded as floats where:
      # - Integer part: Unix timestamp for time-based ordering
      # - Decimal part: Metadata (permissions, flags, etc.)
      #
      # Format: [timestamp].[metadata]
      # Example: 1704067200.125 = Jan 1, 2024 12:00:00 UTC with permission level 125
      #
      # This allows Redis to maintain time-based ordering while carrying metadata
      # that can be extracted when needed without additional Redis operations.
      module ScoreEncoding
        # Maximum value for metadata to preserve precision (3 decimal places)
        MAX_METADATA = 999
        METADATA_PRECISION = 1000.0

        # Permission levels that can be encoded in scores
        PERMISSION_LEVELS = {
          none: 0,
          read: 100,
          write: 200,
          admin: 300,
          unknown: 999
        }.freeze

        class << self
          # Encode a timestamp and metadata into a Redis score
          #
          # @param timestamp [Time, Integer] The timestamp to encode
          # @param metadata [Integer, Hash] Metadata to encode (0-999)
          # @return [Float] Encoded score suitable for Redis sorted sets
          #
          # @example Basic encoding
          #   encode_score(Time.now, 42)
          #   #=> 1704067200.042
          #
          # @example Permission encoding
          #   encode_score(Time.now, permission: :write)
          #   #=> 1704067200.200
          def encode_score(timestamp, metadata = 0)
            time_part = timestamp.respond_to?(:to_i) ? timestamp.to_i : timestamp.to_i

            metadata_part = if metadata.is_a?(Hash)
                              encode_metadata_hash(metadata)
                            else
                              validate_metadata(metadata)
                            end

            time_part + (metadata_part / METADATA_PRECISION)
          end

          # Decode a Redis score back into timestamp and metadata
          #
          # @param score [Float] The encoded score
          # @return [Hash] Hash with :timestamp and :metadata keys
          #
          # @example Basic decoding
          #   decode_score(1704067200.042)
          #   #=> { timestamp: 1704067200, metadata: 42 }
          def decode_score(score)
            return { timestamp: 0, metadata: 0 } unless score.is_a?(Numeric)

            time_part = score.to_i
            decimal_part = score - time_part
            metadata_part = (decimal_part * METADATA_PRECISION).round

            {
              timestamp: time_part,
              metadata: metadata_part
            }
          end

          # Encode timestamp with permission level
          #
          # @param timestamp [Time, Integer] The timestamp
          # @param permission [Symbol, Integer] Permission level (:read, :write, :admin, or integer)
          # @return [Float] Encoded score
          #
          # @example
          #   permission_encode(Time.now, :write)
          #   #=> 1704067200.200
          def permission_encode(timestamp, permission)
            permission_value = case permission
                               when Symbol
                                 PERMISSION_LEVELS[permission] || PERMISSION_LEVELS[:unknown]
                               when Integer
                                 validate_metadata(permission)
                               else
                                 0
                               end

            encode_score(timestamp, permission_value)
          end

          # Decode permission level from score
          #
          # @param score [Float] The encoded score
          # @return [Hash] Hash with :timestamp, :permission_level, and :permission keys
          #
          # @example
          #   permission_decode(1704067200.200)
          #   #=> { timestamp: 1704067200, permission_level: 200, permission: :write }
          def permission_decode(score)
            decoded = decode_score(score)
            permission_level = decoded[:metadata]

            permission_symbol = PERMISSION_LEVELS.key(permission_level) || :unknown

            {
              timestamp: decoded[:timestamp],
              permission_level: permission_level,
              permission: permission_symbol
            }
          end

          # Get current timestamp as score (no metadata)
          #
          # @return [Float] Current time as Redis score
          def current_score
            encode_score(Time.now, 0)
          end

          # Create score range for Redis operations based on time bounds
          #
          # @param start_time [Time, nil] Start time (nil for -inf)
          # @param end_time [Time, nil] End time (nil for +inf)
          # @param min_permission [Symbol, Integer, nil] Minimum permission level
          # @return [Array] Array suitable for Redis ZRANGEBYSCORE operations
          #
          # @example Time range
          #   score_range(1.hour.ago, Time.now)
          #   #=> ["1704063600", "1704067200"]
          #
          # @example Permission filter
          #   score_range(nil, nil, min_permission: :read)
          #   #=> ["100", "+inf"]
          def score_range(start_time = nil, end_time = nil, min_permission: nil)
            min_score = if start_time
                          encode_score(start_time, min_permission ? permission_level_value(min_permission) : 0)
                        elsif min_permission
                          encode_score(0, permission_level_value(min_permission))
                        else
                          '-inf'
                        end

            max_score = if end_time
                          encode_score(end_time, MAX_METADATA)
                        else
                          '+inf'
                        end

            [min_score, max_score]
          end

          # Get numeric value for permission level (public method)
          def permission_level_value(permission)
            case permission
            when Symbol
              PERMISSION_LEVELS[permission] || 0
            when Integer
              validate_metadata(permission)
            else
              0
            end
          end

          private

          # Validate metadata is within acceptable range
          def validate_metadata(metadata)
            metadata = metadata.to_i
            unless (0..MAX_METADATA).cover?(metadata)
              raise ArgumentError,
                    "Metadata must be between 0 and #{MAX_METADATA}"
            end

            metadata
          end

          # Encode a hash of metadata into a single integer
          def encode_metadata_hash(metadata_hash)
            if metadata_hash.key?(:permission)
              permission_level_value(metadata_hash[:permission])
            else
              # Simple encoding - just take first numeric value
              metadata_hash.values.find { |v| v.is_a?(Integer) } || 0
            end
          end
        end

        # Instance methods for classes that include this module
        def encode_score(timestamp, metadata = 0)
          ScoreEncoding.encode_score(timestamp, metadata)
        end

        def decode_score(score)
          ScoreEncoding.decode_score(score)
        end

        def permission_encode(timestamp, permission)
          ScoreEncoding.permission_encode(timestamp, permission)
        end

        def permission_decode(score)
          ScoreEncoding.permission_decode(score)
        end

        def current_score
          ScoreEncoding.current_score
        end

        def score_range(start_time = nil, end_time = nil, min_permission: nil)
          ScoreEncoding.score_range(start_time, end_time, min_permission: min_permission)
        end
      end
    end
  end
end
