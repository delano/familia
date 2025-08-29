# frozen_string_literal: true

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
              current_time = Time.now
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

              if new_bits == 0
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
                flag && (bits & flag) > 0
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

            # Set exact permissions for a user (replaces existing)
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
          end
        end
      end
    end
  end
end
