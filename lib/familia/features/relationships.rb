module Familia
  module Features
    # Relationships provides a declarative relationship vocabulary for Familia that builds
    # on the existing RelatableObjects feature. Instead of SQL-inspired `belongs_to`/`has_many`
    # semantics, it provides Redis-native operations that map directly to Redis primitives
    # and make data model intentions explicit.
    #
    # The vocabulary consists of three main relationship types:
    # - tracked_in: Object appears in a sorted set with score metadata
    # - indexed_by: Object is findable by a specific field via hash lookups
    # - member_of: Object belongs to another object's collection
    #
    # Example:
    #
    #   class CustomDomain < Familia::Horreum
    #     feature :relationships
    #
    #     # Domain appears in global values sorted set
    #     tracked_in :values, type: :sorted_set, score: :created_at, cascade: :delete
    #
    #     # Domain can be found by display_domain field
    #     indexed_by :display_domain, in: :display_domains, finder: true
    #
    #     # Domain is a member of a customer's domains collection
    #     member_of Customer, :custom_domains, key: :display_domain
    #   end
    #
    module Relationships
      class RelationshipError < Familia::Problem; end

      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods
        base.include InstanceMethods
      end

      # Instance methods for Relationship functionality
      module InstanceMethods
        # Initialize relationships and ensure proper inheritance chain
        def init
          super if defined?(super) # Only call if parent has init
        end

        # Override save to maintain relationships automatically
        def save(update_expiration: true)
          result = super
          maintain_relationships(:save) if result
          result
        end

        # Override destroy! to maintain relationships automatically
        def destroy!
          maintain_relationships(:destroy)
          super
        end

        private

        def maintain_relationships(operation)
          self.class.relationships.each do |rel|
            rel.maintain(self, operation)
          end
        end
      end

      # Class methods for Relationship functionality
      module ClassMethods
        # Get all defined relationships
        def relationships
          @relationships ||= []
        end

        # tracked_in: Object appears in a sorted set (ZADD/ZREM operations) with score metadata
        #
        # @param collection [Symbol] Name of the collection
        # @param type [Symbol] Type of Redis data structure (:sorted_set, :set, :list)
        # @param score [Symbol, Proc] Score value or method for sorted sets
        # @param cascade [Symbol] Cascade behavior (:delete, :nullify, :restrict)
        #
        # @example
        #   tracked_in :values, type: :sorted_set, score: :created_at, cascade: :delete
        #   tracked_in Customer, :domains, score: -> { permission_encode(created_at, permission_level) }
        #
        def tracked_in(collection, type: :sorted_set, score: nil, cascade: nil)
          rel = TrackedInRelationship.new(
            collection: collection,
            type: type,
            score: score,
            cascade: cascade
          )
          relationships << rel

          # Generate class methods for collection management
          rel.generate_class_methods(self)
        end

        # indexed_by: Object is findable by a specific field (hash lookups)
        #
        # @param field [Symbol] Field name to index
        # @param in [Symbol] Name of the index hash
        # @param finder [Boolean] Whether to generate finder method
        #
        # @example
        #   indexed_by :display_domain, in: :display_domains, finder: true
        #   # Generates: CustomDomain.from_display_domain(value)
        #
        def indexed_by(field, in: nil, finder: false)
          index_name = binding.local_variable_get(:in) || :"#{field}_index"

          rel = IndexedByRelationship.new(
            field: field,
            index_name: index_name,
            finder: finder
          )
          relationships << rel

          # Generate finder method if requested
          rel.generate_finder_method(self) if finder

          # Ensure we have the index hash
          class_hashkey index_name unless respond_to?(index_name)
        end

        # member_of: Object belongs to another object's collection
        #
        # @param owner_class [Class] The class that owns this object
        # @param collection [Symbol] Name of the collection on the owner
        # @param key [Symbol] Field to use as the collection value (defaults to identifier)
        #
        # @example
        #   member_of Customer, :custom_domains, key: :display_domain
        #
        def member_of(owner_class, collection, key: nil)
          rel = MemberOfRelationship.new(
            owner_class: owner_class,
            collection: collection,
            key: key || :identifier
          )
          relationships << rel

          # Generate instance methods for membership management
          rel.generate_instance_methods(self)
        end
      end

      # Base class for relationship metadata
      class RelationshipMetadata
        attr_reader :options

        def initialize(**options)
          @options = options
        end

        def maintain(object, operation)
          case operation
          when :save
            handle_save(object)
          when :destroy
            handle_destroy(object)
          end
        end

        protected

        def handle_save(object)
          # Override in subclasses
        end

        def handle_destroy(object)
          # Override in subclasses
        end
      end

      # Relationship for tracked_in declarations
      class TrackedInRelationship < RelationshipMetadata
        def collection
          @options[:collection]
        end

        def type
          @options[:type]
        end

        def score
          @options[:score]
        end

        def cascade
          @options[:cascade]
        end

        def generate_class_methods(klass)
          collection_name = collection
          rel_type = type
          score
          relationship = self

          # Ensure we have the appropriate data structure
          case rel_type
          when :sorted_set
            klass.class_sorted_set collection_name unless klass.respond_to?(collection_name)
          when :set
            klass.class_set collection_name unless klass.respond_to?(collection_name)
          when :list
            klass.class_list collection_name unless klass.respond_to?(collection_name)
          end

          # Generate add method
          klass.define_singleton_method :"add_to_#{collection_name}" do |object|
            case rel_type
            when :sorted_set
              score_value = relationship.send(:calculate_score, object)
              send(collection_name).add(score_value, object.identifier)
            when :set
              send(collection_name).add(object.identifier)
            when :list
              send(collection_name).push(object.identifier)
            end
          end

          # Generate remove method
          klass.define_singleton_method :"remove_from_#{collection_name}" do |object|
            case rel_type
            when :sorted_set
              send(collection_name).remove(object.identifier)
            when :set
              send(collection_name).remove(object.identifier)
            when :list
              send(collection_name).remove(object.identifier)
            end
          end

          # For sorted sets, add score update method
          return unless rel_type == :sorted_set

          klass.define_singleton_method :"update_score_in_#{collection_name}" do |object, new_score|
            send(collection_name).add(new_score, object.identifier)
          end
        end

        protected

        def handle_save(object)
          # Add to collection when object is saved
          object.class.send(:"add_to_#{collection}", object)
        end

        def handle_destroy(object)
          case cascade
          when :delete
            object.class.send(:"remove_from_#{collection}", object)
          when :restrict
            if object.class.send(collection).member?(object.identifier)
              raise RelationshipError, "Cannot delete: object still referenced in #{collection}"
            end
            # :nullify - do nothing, keep in collection
          end
        end

        private

        def calculate_score(object)
          case score
          when Symbol
            object.send(score)
          when Proc
            object.instance_eval(&score)
          when Numeric
            score
          else
            Time.now.to_f
          end
        end
      end

      # Relationship for indexed_by declarations
      class IndexedByRelationship < RelationshipMetadata
        def field
          @options[:field]
        end

        def index_name
          @options[:index_name]
        end

        def finder
          @options[:finder]
        end

        def generate_finder_method(klass)
          field_name = field
          index_name = self.index_name

          klass.define_singleton_method :"from_#{field_name}" do |value|
            identifier = send(index_name).get(value)
            return nil unless identifier

            begin
              from_identifier(identifier)
            rescue Familia::Problem
              nil
            end
          end
        end

        protected

        def handle_save(object)
          # Update index when object is saved
          field_value = object.send(field)
          return if field_value.nil?

          object.class.send(index_name)[field_value] = object.identifier
        end

        def handle_destroy(object)
          # Remove from index when object is destroyed
          field_value = object.send(field)
          return if field_value.nil?

          object.class.send(index_name).remove_field(field_value)
        end
      end

      # Relationship for member_of declarations
      class MemberOfRelationship < RelationshipMetadata
        def owner_class
          @options[:owner_class]
        end

        def collection
          @options[:collection]
        end

        def key
          @options[:key]
        end

        def generate_instance_methods(klass)
          # Extract just the class name without namespace, convert to lowercase
          owner_class_name = owner_class.name.split('::').last.downcase
          collection_name = collection
          key_field = key

          # Generate add_to_owner method
          klass.define_method :"add_to_#{owner_class_name}" do |owner|
            key_value = send(key_field)
            collection_obj = owner.send(collection_name)

            # Handle different collection types
            case collection_obj.class.name
            when 'Familia::SortedSet'
              # For sorted sets, use current timestamp as score
              collection_obj.add(Time.now.to_f, key_value)
            when 'Familia::Set'
              collection_obj.add(key_value)
            when 'Familia::List'
              collection_obj.push(key_value)
            else
              # Default to add method
              collection_obj.add(key_value)
            end
          end

          # Generate remove_from_owner method
          klass.define_method :"remove_from_#{owner_class_name}" do |owner|
            key_value = send(key_field)
            owner.send(collection_name).remove(key_value)
          end
        end

        protected

        def handle_destroy(object)
          # Remove from all owner collections - this would require
          # additional tracking or explicit cleanup
        end
      end

      Familia::Base.add_feature self, :relationships, depends_on: [:relatable_objects]
    end
  end
end
