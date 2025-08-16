# lib/familia/features/relatable_objects.rb

module Familia
  module Features
    class RelatableObjectError < Familia::Problem; end

    # RelatableObjects is a feature that provides a standardized system for managing
    # object relationships and ownership in Familia applications. It enables objects
    # to have unique identifiers, external references, and ownership relationships
    # while maintaining API versioning and secure object management.
    #
    # This feature introduces a dual-identifier system:
    # - Object ID (objid): Internal UUID v7 for system use
    # - External ID (extid): External-facing identifier for API consumers
    #
    # Objects can own other objects through a centralized ownership registry with
    # validation to prevent self-ownership and enforce type checking.
    #
    # Example:
    #
    #   class Customer < Familia::Horreum
    #     feature :relatable_objects
    #     
    #     field :name, :email, :plan
    #   end
    #
    #   class Domain < Familia::Horreum
    #     feature :relatable_objects
    #     
    #     field :name, :dns_zone
    #   end
    #
    #   # Create objects with automatic ID generation
    #   customer = Customer.new(name: "Acme Corp", email: "admin@acme.com")
    #   domain = Domain.new(name: "acme.com")
    #
    #   # IDs are lazily generated on first access
    #   customer.objid   # => "018c3f8e-7b2a-7f4a-9d8e-1a2b3c4d5e6f" (UUID v7)
    #   customer.extid   # => "ext_3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z" (54 chars)
    #
    #   # Establish ownership (implementation-specific)
    #   Customer.owners.set(domain.objid, customer.objid)
    #
    #   # Check ownership relationships
    #   domain.owner?(customer)  # => true
    #   domain.owned?           # => true
    #   customer.owner?(domain) # => false
    #
    # Automatic ID Generation:
    #
    # Both identifiers are generated lazily when first accessed:
    # - objid: UUID v7 with timestamp ordering for better database performance
    # - extid: 54-character external identifier with "ext_" prefix
    #
    # Alternative accessor methods are provided for clarity:
    #   customer.relatable_objid       # Same as objid  
    #   customer.external_identifier   # Same as extid
    #
    # API Version Tracking:
    #
    # Each object automatically tracks its API version for evolution support:
    #   customer.api_version  # => "v2" (automatically set)
    #
    # Object Relationship Management:
    #
    # The ownership system uses Redis hash structures to track relationships:
    # - owners: Maps owned object IDs to owner object IDs
    # - Prevents self-ownership and enforces type validation
    # - Supports complex ownership hierarchies
    #
    # Security Considerations:
    #
    # - External IDs should be used in all public APIs
    # - Internal objids should never be exposed to end users
    # - Ownership validation prevents unauthorized access
    # - Type checking ensures relationship integrity
    #
    # Integration with Multi-Tenant Applications:
    #
    #   class Organization < Familia::Horreum
    #     feature :relatable_objects
    #     field :name, :plan, :domain
    #   end
    #
    #   class User < Familia::Horreum
    #     feature :relatable_objects
    #     field :email, :name, :role
    #   end
    #
    #   # Establish organizational ownership
    #   org = Organization.create(name: "Acme Corp")
    #   user = User.create(email: "john@acme.com", name: "John Doe")
    #   Organization.owners.set(user.objid, org.objid)
    #
    #   # Query relationships
    #   user.owned?  # => true
    #   user.owner?(org)  # => false (user doesn't own org)
    #   org.owner?(user)  # => true (org owns user)
    #
    module RelatableObjects
      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods

        # Set up class-level data structures for relationship tracking
        base.class_sorted_set :relatable_objids
        base.class_hashkey :owners

        # Define core relatable object fields
        # NOTE: We do not automatically assign the objid field as the
        # main identifier field. That's up to the implementing class.
        base.field :objid
        base.field :extid
        base.field :api_version

        base.extend(ClassMethods)

        # prepend ensures our methods execute BEFORE field-generated accessors
        # include would place them AFTER, but they'd never execute because
        # attr_reader doesn't call super - it just returns the instance variable
        #
        # Method lookup chain:
        #   prepend:  [InstanceMethods] → [Field Methods] → [Parent]
        #   include:  [Field Methods] → [InstanceMethods] → [Parent]
        #              (stops here, no super)    (never reached)
        #
        base.prepend(InstanceMethods)
      end

      module InstanceMethods
        # We lazily generate the object ID and external ID when they are first
        # accessed so that we can instantiate and load existing objects, without
        # eagerly generating them, only to be overridden by the storage layer.
        #
        def init
          super if defined?(super) # Only call if parent has init

          @api_version ||= 'v2'
        end

        def objid
          @objid ||= begin # lazy loader
            generated_id = self.class.generate_objid
            # Using the attr_writer method ensures any future Familia
            # enhancements to the setter are properly invoked (as opposed
            # to directly assigning @objid).
            self.objid   = generated_id
          end
        end
        alias relatable_objid objid

        def extid
          @extid ||= begin # lazy loader
            generated_id = self.class.generate_extid
            self.extid   = generated_id
          end
        end
        alias external_identifier extid

        # Check if the given customer is the owner of this domain
        #
        # @param cust [V2::Customer, String] The customer object or customer ID to check
        # @return [Boolean] true if the customer is the owner, false otherwise
        def owner?(related_object)
          self.class.relatable?(related_object) do
            # Check the hash (our objid => related_object's objid)
            owner_objid = self.class.owners.get(objid).to_s
            return false if owner_objid.empty?

            owner_objid.eql?(related_object.objid)
          end
        end

        def owned?
          # We can only have an owner if we are relatable ourselves.
          return false unless is_a?(RelatableObject)

          # If our object identifier is present, we have an owner
          self.class.owners.key?(objid)
        end
      end

      module ClassMethods
        def relatable?(obj, &)
          is_relatable = obj.is_a?(RelatableObject)
          err_klass = V2::Features::RelatableObjectError
          raise err_klass, 'Not relatable object' unless is_relatable
          raise err_klass, 'No self-ownership' if obj.class == self

          block_given? ? yield : is_relatable
        end

        def find_by_objid(objid)
          return nil if objid.to_s.empty?

          if Familia.debug?
            reference = caller(1..1).first
            Familia.trace :FIND_BY_OBJID, Familia.dbclient(uri), objkey, reference
          end

          find_by_key objkey
        end

        def generate_objid
          SecureRandom.uuid_v7
        end

        # Guaranteed length of 54
        def generate_extid
          format('ext_%s', Familia.generate_id)
        end

        # Set ownership relationship between objects
        #
        # Establishes that the owner object owns the owned object by storing
        # the relationship in the owners hash.
        #
        # @param owned_object [RelatableObjects] The object to be owned
        # @param owner_object [RelatableObjects] The object that will own
        # @return [Boolean] Success of the operation
        #
        # @example Set customer as domain owner
        #   Customer.set_ownership(domain, customer)
        #
        def set_ownership(owned_object, owner_object)
          relatable?(owned_object)
          relatable?(owner_object)

          owners.set(owned_object.objid, owner_object.objid)
        end

        # Remove ownership relationship
        #
        # @param owned_object [RelatableObjects] The owned object
        # @return [Boolean] Success of the operation
        #
        def remove_ownership(owned_object)
          relatable?(owned_object)
          owners.delete(owned_object.objid)
        end

        # Get all objects owned by the given owner
        #
        # @param owner_object [RelatableObjects] The owner object
        # @return [Array<String>] Array of owned object IDs
        #
        def owned_by(owner_object)
          relatable?(owner_object)

          owned_objids = owners.keys.select do |owned_objid|
            owners.get(owned_objid) == owner_object.objid
          end

          owned_objids.map { |objid| find_by_objid(objid) }.compact
        end
      end

      Familia::Base.add_feature self, :relatable_objects
    end
  end
end
