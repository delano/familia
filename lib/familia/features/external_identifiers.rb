# lib/familia/features/external_identifiers.rb

require_relative 'external_identifiers/external_identifier_field_type'

module Familia
  module Features

    # Familia::Features::ExternalIdentifiers
    #
    module ExternalIdentifiers
      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods

        # Ensure default prefix is set in feature options
        base.add_feature_options(:external_identifiers, prefix: 'ext')

        # Add class-level mapping for extid -> id lookups
        base.class_hashkey :extid_lookup

        # Register the extid field using our custom field type
        base.register_field_type(
          ExternalIdentifiers::ExternalIdentifierFieldType.new(:extid, as: :extid, fast_method: false)
        )
      end

      # ExternalIdentifiers::ClassMethods
      #
      module ClassMethods
        def generate_extid(objid = nil)
          unless features_enabled.include?(:object_identifiers)
            raise Familia::Problem,
                  'ExternalIdentifiers requires ObjectIdentifiers feature'
          end
          return nil if objid.to_s.empty?

          objid_hex = objid.to_s.delete('-')
          external_part = Familia.shorten_to_external_id(objid_hex, base: 36)
          prefix = feature_options(:external_identifiers)[:prefix] || 'ext'
          "#{prefix}_#{external_part}"
        end

        # Find an object by its external identifier
        #
        # @param extid [String] The external identifier to search for
        # @return [Object, nil] The object if found, nil otherwise
        #
        def find_by_extid(extid)
          return nil if extid.to_s.empty?

          if Familia.debug?
            reference = caller(1..1).first
            Familia.trace :FIND_BY_EXTID, Familia.dbclient, extid, reference
          end

          # Look up the primary ID from the external ID mapping
          primary_id = extid_lookup[extid]
          return nil if primary_id.nil?

          # Find the object by its primary ID
          find_by_id(primary_id)
        rescue Familia::NotFound
          # If the object was deleted but mapping wasn't cleaned up
          extid_lookup.del(extid)
          nil
        end
      end

      # Generate external identifier deterministically from objid
      def generate_external_identifier
        return nil unless respond_to?(:objid)

        current_objid = objid
        return nil if current_objid.nil? || current_objid.to_s.empty?

        # Convert objid to hex string for processing
        objid_hex = current_objid.delete('-') # Remove UUID hyphens if present

        # Generate deterministic external ID using SecureIdentifier
        external_part = Familia.shorten_to_external_id(objid_hex, base: 36)

        # Get prefix from feature options, default to "ext"
        options = self.class.feature_options(:external_identifiers)
        prefix = options[:prefix] || 'ext'

        "#{prefix}_#{external_part}"
      end

      def external_identifier
        extid
      end

      def init
        super if defined?(super)
        # External IDs are generated from objid, so no additional setup needed
      end

      def destroy!
        # Clean up extid mapping when object is destroyed
        current_extid = instance_variable_get(:@extid)
        if current_extid
          self.class.extid_lookup.del(current_extid)
        end

        super if defined?(super)
      end

      Familia::Base.add_feature self, :external_identifiers, depends_on: [:object_identifiers]
    end
  end
end
