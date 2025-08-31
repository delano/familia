# lib/familia/features/relationships/score_encoding.rb

module Familia
  module Features
    module Relationships
      # Score encoding using bit flags for permissions
      #
      # Encodes permissions as bit flags in the decimal portion of Redis sorted set scores:
      # - Integer part: Unix timestamp for time-based ordering
      # - Decimal part: 8-bit permission flags (0-255)
      #
      # Format: [timestamp].[permission_bits]
      # Example: 1704067200.037 = Jan 1, 2024 with read(1) + write(4) + delete(32) = 37
      #
      # Bit positions:
      #   0: read      - View/list items
      #   1: append    - Add new items
      #   2: write     - Modify existing items
      #   3: edit      - Edit metadata
      #   4: configure - Change settings
      #   5: delete    - Remove items
      #   6: transfer  - Change ownership
      #   7: admin     - Full control
      #
      # This allows combining permissions (read + delete without write) and efficient
      # permission checking using bitwise operations while maintaining time-based ordering.
      module ScoreEncoding
        # Maximum value for metadata to preserve precision (3 decimal places)
        # For 8-bit permission system, max value is 255
        MAX_METADATA = 255
        METADATA_PRECISION = 1000.0

        # Permission bit flags (8-bit system)
        PERMISSION_FLAGS = {
          none:      0b00000000,  # 0   - No permissions
          read:      0b00000001,  # 1   - View/list
          append:    0b00000010,  # 2   - Add new items
          write:     0b00000100,  # 4   - Modify existing
          edit:      0b00001000,  # 8   - Edit metadata
          configure: 0b00010000,  # 16  - Change settings
          delete:    0b00100000,  # 32  - Remove items
          transfer:  0b01000000,  # 64  - Change ownership
          admin:     0b10000000   # 128 - Full control
        }.freeze

        # Predefined permission combinations
        PERMISSION_ROLES = {
          viewer:     PERMISSION_FLAGS[:read],
          editor:     PERMISSION_FLAGS[:read] | PERMISSION_FLAGS[:write] | PERMISSION_FLAGS[:edit],
          moderator:  PERMISSION_FLAGS[:read] | PERMISSION_FLAGS[:write] | PERMISSION_FLAGS[:edit] | PERMISSION_FLAGS[:delete],
          admin:      0b11111111  # All permissions
        }.freeze

        # Categorical masks for efficient broad queries
        PERMISSION_CATEGORIES = {
          readable:       0b00000001,  # Has basic access
          content_editor: 0b00001110,  # Can modify content (append|write|edit)
          administrator:  0b11110000,  # Has any admin powers
          privileged:     0b11111110,  # Has beyond read-only
          owner:          0b11111111   # All permissions
        }.freeze

        # Legacy permission level mapping for backward compatibility
        PERMISSION_LEVELS = {
          none:      0,
          read:      1,
          append:    2,
          write:     4,
          edit:      8,
          configure: 16,
          delete:    32,
          transfer:  64,
          admin:     128,
          unknown:   0
        }.freeze

        class << self
          # Get permission level value for a permission symbol
          #
          # @param permission [Symbol] Permission symbol to get value for
          # @return [Integer] Bit flag value for the permission
          def permission_level_value(permission)
            PERMISSION_FLAGS[permission] || 0
          end

          # Encode timestamp and permission (alias for encode_score)
          #
          # @param timestamp [Time, Integer] The timestamp to encode
          # @param permission [Symbol, Integer, Array] Permission(s) to encode
          # @return [Float] Encoded score suitable for Redis sorted sets
          def permission_encode(timestamp, permission)
            encode_score(timestamp, permission)
          end

          # Decode score into legacy permission format
          #
          # @param score [Float] The encoded score
          # @return [Hash] Hash with legacy permission format
          def permission_decode(score)
            decoded = decode_score(score)
            {
              timestamp: decoded[:timestamp],
              permission_level: decoded[:permissions],
              permission: first_permission_symbol(decoded[:permissions])
            }
          end

          # Helper: Get the first matching permission symbol from a bitmask
          #
          # @param permissions [Integer] Bitmask of permissions
          # @return [Symbol, nil] The first matching permission symbol, or nil if none
          def first_permission_symbol(permissions)
            PERMISSION_FLAGS.each do |sym, bit|
              return sym if (permissions & bit) != 0 && bit != 0
            end
            nil
          end

          # Encode a timestamp and permissions into a Redis score
          #
          # @param timestamp [Time, Integer] The timestamp to encode
          # @param permissions [Integer, Symbol, Array] Permissions to encode
          # @return [Float] Encoded score suitable for Redis sorted sets
          #
          # @example Basic encoding with bit flag
          #   encode_score(Time.now, 5)  # read(1) + write(4) = 5
          #   #=> 1704067200.005
          #
          # @example Permission symbol encoding
          #   encode_score(Time.now, :read)
          #   #=> 1704067200.001
          #
          # @example Multiple permissions
          #   encode_score(Time.now, [:read, :write, :delete])
          #   #=> 1704067200.037
          def encode_score(timestamp, permissions = 0)
            time_part = timestamp.respond_to?(:to_i) ? timestamp.to_i : timestamp

            permission_bits = case permissions
                              when Symbol
                                PERMISSION_ROLES[permissions] || PERMISSION_FLAGS[permissions] || 0
                              when Array
                                # Support array of permission symbols
                                permissions.reduce(0) { |acc, p| acc | (PERMISSION_FLAGS[p] || 0) }
                              when Integer
                                validate_permission_bits(permissions)
                              else
                                0
                              end

            time_part + (permission_bits / METADATA_PRECISION)
          end

          # Decode a Redis score back into timestamp and permissions
          #
          # @param score [Float] The encoded score
          # @return [Hash] Hash with :timestamp, :permissions, and :permission_list keys
          #
          # @example Basic decoding
          #   decode_score(1704067200.037)
          #   #=> { timestamp: 1704067200, permissions: 37, permission_list: [:read, :write, :delete] }
          def decode_score(score)
            return { timestamp: 0, permissions: 0, permission_list: [] } unless score.is_a?(Numeric)

            time_part = score.to_i
            permission_bits = ((score - time_part) * METADATA_PRECISION).round

            {
              timestamp: time_part,
              permissions: permission_bits,
              permission_list: decode_permission_flags(permission_bits)
            }
          end

          # Check if score has specific permissions
          #
          # @param score [Float] The encoded score
          # @param permissions [Array<Symbol>] Permissions to check
          # @return [Boolean] True if all permissions are present
          #
          # @example
          #   permission?(1704067200.005, :read)  # score has read(1) + write(4)
          #   #=> true
          def permission?(score, *permissions)
            decoded = decode_score(score)
            permission_bits = decoded[:permissions]

            permissions.all? do |perm|
              flag = PERMISSION_FLAGS[perm]
              flag && (permission_bits & flag) > 0
            end
          end

          # Add permissions to existing score
          #
          # @param score [Float] The existing encoded score
          # @param permissions [Array<Symbol>] Permissions to add
          # @return [Float] New score with added permissions
          #
          # @example
          #   add_permissions(1704067200.001, :write, :delete)  # add write(4) + delete(32) to read(1)
          #   #=> 1704067200.037
          def add_permissions(score, *permissions)
            decoded = decode_score(score)
            current_bits = decoded[:permissions]

            new_bits = permissions.reduce(current_bits) do |acc, perm|
              acc | (PERMISSION_FLAGS[perm] || 0)
            end

            encode_score(decoded[:timestamp], new_bits)
          end

          # Remove permissions from existing score
          #
          # @param score [Float] The existing encoded score
          # @param permissions [Array<Symbol>] Permissions to remove
          # @return [Float] New score with removed permissions
          #
          # @example
          #   remove_permissions(1704067200.037, :write)  # remove write(4) from read(1)+write(4)+delete(32)
          #   #=> 1704067200.033
          def remove_permissions(score, *permissions)
            decoded = decode_score(score)
            current_bits = decoded[:permissions]

            new_bits = permissions.reduce(current_bits) do |acc, perm|
              acc & ~(PERMISSION_FLAGS[perm] || 0)
            end

            encode_score(decoded[:timestamp], new_bits)
          end

          # Create score range for permissions
          #
          # @param min_permissions [Array<Symbol>, nil] Minimum required permissions
          # @param max_permissions [Array<Symbol>, nil] Maximum allowed permissions
          # @return [Array<Float>] Min and max scores for Redis range queries
          #
          # @example
          #   permission_range([:read], [:read, :write])
          #   #=> [0.001, 0.005]
          def permission_range(min_permissions = [], max_permissions = nil)
            min_bits = Array(min_permissions).reduce(0) { |acc, p| acc | (PERMISSION_FLAGS[p] || 0) }
            max_bits = max_permissions ? Array(max_permissions).reduce(0) { |acc, p| acc | (PERMISSION_FLAGS[p] || 0) } : 255

            [min_bits / METADATA_PRECISION, max_bits / METADATA_PRECISION]
          end

          # Get current timestamp as score (no permissions)
          #
          # @return [Float] Current time as Redis score
          def current_score
            encode_score(Time.now, 0)
          end

          # Create score range for Redis operations based on time bounds
          #
          # @param start_time [Time, nil] Start time (nil for -inf)
          # @param end_time [Time, nil] End time (nil for +inf)
          # @param min_permissions [Array<Symbol>, nil] Minimum required permissions
          # @return [Array] Array suitable for Redis ZRANGEBYSCORE operations
          #
          # @example Time range
          #   score_range(1.hour.ago, Time.now)
          #   #=> [1704063600.0, 1704067200.255]
          #
          # @example Permission filter
          #   score_range(nil, nil, min_permissions: [:read])
          #   #=> [0.001, "+inf"]
          def score_range(start_time = nil, end_time = nil, min_permissions: nil)
            min_bits = min_permissions ? Array(min_permissions).reduce(0) { |acc, p| acc | (PERMISSION_FLAGS[p] || 0) } : 0

            min_score = if start_time
                          encode_score(start_time, min_bits)
                        elsif min_permissions
                          encode_score(0, min_bits)
                        else
                          '-inf'
                        end

            max_score = if end_time
                          encode_score(end_time, 255)  # Use max valid permission bits
                        else
                          '+inf'
                        end

            [min_score, max_score]
          end

          # Decode permission bits into array of permission symbols
          #
          # @param bits [Integer] Permission bits to decode
          # @return [Array<Symbol>] Array of permission symbols
          def decode_permission_flags(bits)
            PERMISSION_FLAGS.select { |_name, flag| (bits & flag) > 0 }.keys
          end

          # Check broad permission categories
          #
          # @param score [Float] The encoded score
          # @param category [Symbol] Category to check (:readable, :content_editor, :administrator, etc.)
          # @return [Boolean] True if score meets the category requirements
          def category?(score, category)
            decoded = decode_score(score)
            permission_bits = decoded[:permissions]

            mask = PERMISSION_CATEGORIES[category]
            return false unless mask

            (permission_bits & mask) > 0
          end

          # Filter collection by permission category
          #
          # @param scores [Array<Float>] Array of scores to filter
          # @param category [Symbol] Category to filter by
          # @return [Array<Float>] Scores matching the category
          def filter_by_category(scores, category)
            mask = PERMISSION_CATEGORIES[category]
            return [] unless mask

            scores.select do |score|
              permission_bits = ((score % 1) * METADATA_PRECISION).round
              (permission_bits & mask) > 0
            end
          end

          # Get permission tier for score
          #
          # @param score [Float] The encoded score
          # @return [Symbol] Permission tier (:administrator, :content_editor, :viewer, :none)
          def permission_tier(score)
            decoded = decode_score(score)
            bits = decoded[:permissions]

            if (bits & PERMISSION_CATEGORIES[:administrator]) > 0
              :administrator
            elsif (bits & PERMISSION_CATEGORIES[:content_editor]) > 0
              :content_editor
            elsif (bits & PERMISSION_CATEGORIES[:readable]) > 0
              :viewer
            else
              :none
            end
          end

          # Efficient bulk categorization
          #
          # @param scores [Array<Float>] Array of scores to categorize
          # @return [Hash] Hash mapping tiers to arrays of scores
          def categorize_scores(scores)
            scores.group_by { |score| permission_tier(score) }
          end

          # Check if permissions meet minimum category
          #
          # @param permission_bits [Integer] Permission bits to check
          # @param category [Symbol] Category to check against
          # @return [Boolean] True if permissions meet the category requirements
          def meets_category?(permission_bits, category)
            mask = PERMISSION_CATEGORIES[category]
            return false unless mask

            case category
            when :readable
              permission_bits.positive?  # Any permission implies read
            when :privileged
              permission_bits > 1 # More than just read
            when :administrator
              permission_bits.anybits?(PERMISSION_CATEGORIES[:administrator])
            else
              permission_bits.anybits?(mask)
            end
          end

          # Range queries for categorical filtering
          #
          # @param category [Symbol] Category to create range for
          # @param start_time [Time, nil] Optional start time filter
          # @param end_time [Time, nil] Optional end time filter
          # @return [Array<String>] Min and max range strings for Redis queries
          def category_score_range(category, start_time = nil, end_time = nil)
            mask = PERMISSION_CATEGORIES[category] || 0

            # Any permission matching the category mask
            min_score = start_time ? start_time.to_i : 0
            max_score = end_time ? end_time.to_i : Time.now.to_i

            # Return range that includes any matching permissions
            ["#{min_score}.000", "#{max_score}.999"]
          end

          private

          # Validate permission bits are within acceptable range
          #
          # @param bits [Integer] Permission bits to validate
          # @return [Integer] Validated permission bits
          # @raise [ArgumentError] If bits are outside 0-255 range
          def validate_permission_bits(bits)
            raise ArgumentError, 'Permission bits must be 0-255' unless (0..255).cover?(bits)

            bits
          end
        end

        # Instance methods for classes that include this module
        def encode_score(timestamp, permissions = 0)
          ScoreEncoding.encode_score(timestamp, permissions)
        end

        def decode_score(score)
          ScoreEncoding.decode_score(score)
        end

        def permission?(score, *permissions)
          ScoreEncoding.permission?(score, *permissions)
        end

        def add_permissions(score, *permissions)
          ScoreEncoding.add_permissions(score, *permissions)
        end

        def remove_permissions(score, *permissions)
          ScoreEncoding.remove_permissions(score, *permissions)
        end

        def permission_range(min_permissions = [], max_permissions = nil)
          ScoreEncoding.permission_range(min_permissions, max_permissions)
        end

        def current_score
          ScoreEncoding.current_score
        end

        def score_range(start_time = nil, end_time = nil, min_permissions: nil)
          ScoreEncoding.score_range(start_time, end_time, min_permissions: min_permissions)
        end

        # Legacy method aliases for backward compatibility
        def permission_encode(timestamp, permission)
          ScoreEncoding.permission_encode(timestamp, permission)
        end

        def permission_decode(score)
          ScoreEncoding.permission_decode(score)
        end
      end
    end
  end
end
