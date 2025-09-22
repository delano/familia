# lib/familia/features/relationships/permission_management.rb

module Familia
  module Features
    module Relationships
      # Permission management module for object-level access control
      #
      # Provides methods for granting, revoking, and checking permissions on objects
      # using the bit-encoded permission system from ScoreEncoding.
      #
      # Usage:
      #   class Document < Familia::Horreum
      #     include Familia::Features::Relationships::PermissionManagement
      #     permission_tracking :user_permissions
      #   end
      #
      #   doc.grant(user, :read, :write)
      #   doc.can?(user, :read)  #=> true
      #   doc.revoke(user, :write)
      #   doc.permissions_for(user)  #=> [:read]
      module PermissionManagement
        def self.included(base)
          base.extend(ClassMethods)
        end

        # Relationships::ClassMethods
        #
        module ClassMethods
          # Enable permission tracking for this class
          #
          # @param field_name [Symbol] Name of the hash field to store permissions
          #
          # @example
          #   class Document < Familia::Horreum
          #     permission_tracking :user_permissions
          #   end
          def permission_tracking(field_name = :permissions)
            # Define a hashkey for storing per-user permissions
            hashkey field_name

            # Grant permissions to a user for this object
            #
            # @param user [Object] User or user identifier
            # @param permissions [Array<Symbol>] Permissions to grant
            #
            # @example
            #   document.grant(user, :read, :write, :edit)
            define_method :grant do |user, *permissions|
              user_key = user.respond_to?(:identifier) ? user.identifier : user.to_s

              # Get current score from any sorted set this object belongs to
              # For simplicity, we'll create a new timestamp-based score
              current_time = Familia.now
              new_score = ScoreEncoding.encode_score(current_time, permissions)

              # Store permission bits in hash for quick lookup
              decoded = ScoreEncoding.decode_score(new_score)
              send(field_name)[user_key] = decoded[:permissions]
            end

            # Revoke permissions from a user for this object
            #
            # @param user [Object] User or user identifier
            # @param permissions [Array<Symbol>] Permissions to revoke
            #
            # @example
            #   document.revoke(user, :write, :edit)
            define_method :revoke do |user, *permissions|
              user_key = user.respond_to?(:identifier) ? user.identifier : user.to_s
              current_bits = send(field_name)[user_key].to_i

              # Remove the specified permission bits
              new_bits = permissions.reduce(current_bits) do |acc, perm|
                acc & ~(ScoreEncoding::PERMISSION_FLAGS[perm] || 0)
              end

              if new_bits.zero?
                send(field_name).remove_field(user_key)
              else
                send(field_name)[user_key] = new_bits
              end
            end

            # Check if user has specific permissions for this object
            #
            # @param user [Object] User or user identifier
            # @param permissions [Array<Symbol>] Permissions to check
            # @return [Boolean] True if user has all specified permissions
            #
            # @example
            #   document.can?(user, :read, :write)  #=> true
            define_method :can? do |user, *permissions|
              user_key = user.respond_to?(:identifier) ? user.identifier : user.to_s
              bits = send(field_name)[user_key].to_i

              permissions.all? do |perm|
                flag = ScoreEncoding::PERMISSION_FLAGS[perm]
                flag && bits.anybits?(flag)
              end
            end

            # Get all permissions for a user on this object
            #
            # @param user [Object] User or user identifier
            # @return [Array<Symbol>] Array of permission symbols
            #
            # @example
            #   document.permissions_for(user)  #=> [:read, :write, :edit]
            define_method :permissions_for do |user|
              user_key = user.respond_to?(:identifier) ? user.identifier : user.to_s
              bits = send(field_name)[user_key].to_i
              ScoreEncoding.decode_permission_flags(bits)
            end

            # Add permissions to existing user permissions
            #
            # @param user [Object] User or user identifier
            # @param permissions [Array<Symbol>] Permissions to add
            #
            # @example
            #   document.add_permission(user, :delete, :transfer)
            define_method :add_permission do |user, *permissions|
              user_key = user.respond_to?(:identifier) ? user.identifier : user.to_s
              current_bits = send(field_name)[user_key].to_i

              # Add the specified permission bits
              new_bits = permissions.reduce(current_bits) do |acc, perm|
                acc | (ScoreEncoding::PERMISSION_FLAGS[perm] || 0)
              end

              send(field_name)[user_key] = new_bits
            end

            # UnsortedSet exact permissions for a user (replaces existing)
            #
            # @param user [Object] User or user identifier
            # @param permissions [Array<Symbol>] Permissions to set
            #
            # @example
            #   document.set_permissions(user, :read, :write)
            define_method :set_permissions do |user, *permissions|
              user_key = user.respond_to?(:identifier) ? user.identifier : user.to_s

              if permissions.empty?
                send(field_name).remove_field(user_key)
              else
                permission_bits = permissions.reduce(0) do |acc, perm|
                  acc | (ScoreEncoding::PERMISSION_FLAGS[perm] || 0)
                end
                send(field_name)[user_key] = permission_bits
              end
            end

            # Get all users and their permissions for this object
            #
            # @return [Hash] Hash mapping user keys to permission arrays
            #
            # @example
            #   document.all_permissions
            #   #=> { "user123" => [:read, :write], "user456" => [:read] }
            define_method :all_permissions do
              permissions_hash = send(field_name).hgetall
              permissions_hash.transform_values do |bits|
                ScoreEncoding.decode_permission_flags(bits.to_i)
              end
            end

            # Remove all permissions for all users on this object
            #
            # @example
            #   document.clear_all_permissions
            define_method :clear_all_permissions do
              send(field_name).clear
            end

            # === Two-Stage Filtering Methods ===

            # Stage 1: Valkey/Redis pre-filtering via zset membership
            define_method :accessible_items do |collection_key|
              self.class.dbclient.zrange(collection_key, 0, -1, with_scores: true)
            end

            # Stage 2: Broad categorical filtering on small sets
            define_method :items_by_permission do |collection_key, category = :readable|
              items_with_scores = accessible_items(collection_key)

              # Operating on ~20-100 items, not millions
              filtered = items_with_scores.select do |(_member, score)|
                ScoreEncoding.category?(score, category)
              end

              filtered.map(&:first) # Return just the members
            end

            # Bulk permission check for UI rendering
            define_method :permission_matrix do |collection_key|
              items_with_scores = accessible_items(collection_key)

              {
                total: items_with_scores.size,
                viewable: items_with_scores.count { |(_, s)| ScoreEncoding.category?(s, :readable) },
                editable: items_with_scores.count { |(_, s)| ScoreEncoding.category?(s, :content_editor) },
                administrative: items_with_scores.count { |(_, s)| ScoreEncoding.category?(s, :administrator) },
              }
            end

            # Efficient "can perform any administrative action?" check
            # Note: Currently checks if this object has admin privileges in the collection.
            # The user parameter is reserved for future user-specific permission checking.
            define_method :admin_access? do |_user, collection_key|
              score = self.class.dbclient.zscore(collection_key, identifier)
              return false unless score

              ScoreEncoding.category?(score, :administrator)
            end

            # === Categorical Permission Methods ===

            # Check permission category for user
            #
            # @param user [Object] User object to check category for
            # @param category [Symbol] Category to check (:readable, :content_editor, etc.)
            # @return [Boolean] True if user meets the category requirements
            # @example Check if user has content editor permissions
            #   document.category?(user, :content_editor)  #=> true
            define_method :category? do |user, category|
              user_key = user.respond_to?(:identifier) ? user.identifier : user.to_s
              bits = send(field_name)[user_key].to_i
              ScoreEncoding.meets_category?(bits, category)
            end

            # Get permission tier for user
            #
            # @param user [Object] User object to get tier for
            # @return [Symbol] Permission tier (:administrator, :content_editor, :viewer, :none)
            # @example Get user's permission tier
            #   document.permission_tier_for(user)  #=> :content_editor
            define_method :permission_tier_for do |user|
              user_key = user.respond_to?(:identifier) ? user.identifier : user.to_s
              bits = send(field_name)[user_key].to_i

              # Create a temporary score to use ScoreEncoding.permission_tier
              temp_score = ScoreEncoding.encode_score(Familia.now, bits)
              ScoreEncoding.permission_tier(temp_score)
            end

            # Get users by permission category
            #
            # @param category [Symbol] Category to filter by
            # @return [Array<String>] Array of user keys with the specified category
            # @example Get all content editors
            #   document.users_by_category(:content_editor)  #=> ["user123", "user456"]
            define_method :users_by_category do |category|
              permissions_hash = send(field_name).hgetall
              permissions_hash.select do |_user_key, bits|
                ScoreEncoding.meets_category?(bits.to_i, category)
              end.keys
            end
          end
        end
      end
    end
  end
end
