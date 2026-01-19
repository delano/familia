# lib/familia/features/relationships/participation/through_model_operations.rb
#
# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      module Participation
        # ThroughModelOperations provides lifecycle management for through models
        # in participation relationships.
        #
        # Through models implement the join table pattern, creating an intermediate
        # object between target and participant that can carry additional attributes
        # (e.g., role, permissions, metadata).
        #
        # Key characteristics:
        # - Deterministic identifier: Built from target, participant, and through class
        # - Auto-lifecycle: Created on add, destroyed on remove
        # - Idempotent: Re-adding updates existing model
        # - Atomic: All operations use transactions
        # - Cache-friendly: Auto-updates updated_at for invalidation
        #
        # Example:
        #   class Membership < Familia::Horreum
        #     feature :object_identifier
        #     field :customer_objid
        #     field :domain_objid
        #     field :role
        #     field :updated_at
        #   end
        #
        #   class Domain < Familia::Horreum
        #     participates_in Customer, :domains, through: :Membership
        #   end
        #
        #   # Through model auto-created with deterministic key
        #   customer.add_domains_instance(domain, through_attrs: { role: 'admin' })
        #   # => #<Membership objid="customer:123:domain:456:membership">
        #
        module ThroughModelOperations
          module_function

          # Build a deterministic key for the through model
          #
          # The key format ensures uniqueness and allows direct lookup:
          # {target.prefix}:{target.objid}:{participant.prefix}:{participant.objid}:{through.prefix}
          #
          # @param target [Object] The target instance (e.g., customer)
          # @param participant [Object] The participant instance (e.g., domain)
          # @param through_class [Class] The through model class
          # @return [String] Deterministic key for the through model
          #
          def build_key(target:, participant:, through_class:)
            # Use prefix for Redis key construction (prefix may differ from config_name if explicitly set)
            "#{target.class.prefix}:#{target.objid}:" \
            "#{participant.class.prefix}:#{participant.objid}:" \
            "#{through_class.prefix}"
          end

          # Find or create a through model instance
          #
          # This method is idempotent - calling it multiple times with the same
          # target/participant pair will update the existing through model rather
          # than creating duplicates.
          #
          # The through model's updated_at is set on both create and update for
          # cache invalidation.
          #
          # @param through_class [Class] The through model class
          # @param target [Object] The target instance
          # @param participant [Object] The participant instance
          # @param attrs [Hash] Additional attributes to set on through model
          # @return [Object] The created or updated through model instance
          #
          def find_or_create(through_class:, target:, participant:, attrs: {})
            key = build_key(target: target, participant: participant, through_class: through_class)

            # Try to load existing model - load returns nil if key doesn't exist
            existing = through_class.load(key)

            # Check if we got a valid loaded object using the public API
            # This is called outside transaction boundaries (see participant_methods.rb
            # and target_methods.rb for the transaction boundary documentation)
            if existing&.exists?
              # Update existing through model with validated attributes
              safe_attrs = validated_attrs(through_class, attrs)
              safe_attrs.each { |k, v| existing.send("#{k}=", v) }
              existing.updated_at = Familia.now.to_f if existing.respond_to?(:updated_at=)
              # Save returns boolean, but we want to return the model instance
              existing.save if safe_attrs.any? || existing.respond_to?(:updated_at=)
              existing  # Return the model, not the save result
            else
              # Create new through model with our deterministic key as objid
              # Pass objid during initialization to prevent auto-generation
              inst = through_class.new(objid: key)

              # Set foreign key fields if they exist (validated via respond_to?)
              target_field = "#{target.class.config_name}_objid"
              participant_field = "#{participant.class.config_name}_objid"
              inst.send("#{target_field}=", target.objid) if inst.respond_to?("#{target_field}=")
              inst.send("#{participant_field}=", participant.objid) if inst.respond_to?("#{participant_field}=")

              # Set updated_at for cache invalidation
              inst.updated_at = Familia.now.to_f if inst.respond_to?(:updated_at=)

              # Set custom attributes (validated against field schema)
              safe_attrs = validated_attrs(through_class, attrs)
              safe_attrs.each { |k, v| inst.send("#{k}=", v) }

              # Save returns boolean, but we want to return the model instance
              inst.save
              inst  # Return the model, not the save result
            end
          end

          # Find and destroy a through model instance
          #
          # Used during remove operations to clean up the join table entry.
          #
          # @param through_class [Class] The through model class
          # @param target [Object] The target instance
          # @param participant [Object] The participant instance
          # @return [void]
          #
          def find_and_destroy(through_class:, target:, participant:)
            key = build_key(target: target, participant: participant, through_class: through_class)
            existing = through_class.load(key)
            # Use the public exists? method for a more robust check
            existing&.destroy! if existing&.exists?
          end

          # Validate attribute keys against the through model's field schema
          #
          # This prevents arbitrary method invocation by ensuring only defined
          # fields can be set via the attrs hash.
          #
          # @param through_class [Class] The through model class
          # @param attrs [Hash] Attributes to validate
          # @return [Hash] Only attributes whose keys match defined fields
          #
          def validated_attrs(through_class, attrs)
            return {} if attrs.nil? || attrs.empty?

            valid_fields = through_class.fields.map(&:to_sym)
            attrs.select { |k, _v| valid_fields.include?(k.to_sym) }
          end
        end
      end
    end
  end
end
