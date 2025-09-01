# lib/familia/features/external_identifiers.rb

require_relative 'external_identifiers/external_identifier_field_type'

module Familia
  module Features
    module ExternalIdentifiers
      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods

        # Ensure default prefix is set in feature options if not already present
        base.instance_eval do
          @feature_options ||= {}
          @feature_options[:external_identifiers] ||= {}
          @feature_options[:external_identifiers][:prefix] ||= "ext"
        end

        # Register the extid field using our custom field type
        base.register_field_type(
          ExternalIdentifiers::ExternalIdentifierFieldType.new(:extid, as: :extid, fast_method: false)
        )
      end

      module ClassMethods
        def generate_extid
          # This generates a deterministic external ID from any given objid
          # Used internally by the field type
          raise Familia::Problem, "ExternalIdentifiers requires ObjectIdentifiers feature" unless features_enabled.include?(:object_identifiers)

          # Note: This is called with an objid parameter by the instance method
          # The actual implementation is in the instance method
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

          # This is a simple stub implementation - would need more sophisticated
          # search logic in a real application
          find_by_id(extid)
        rescue Familia::NotFound
          nil
        end
      end

      # Generate external identifier deterministically from objid
      def generate_external_identifier
        return nil unless respond_to?(:objid)

        current_objid = objid
        return nil if current_objid.nil? || current_objid.to_s.empty?

        # Convert objid to hex string for processing
        objid_hex = current_objid.gsub('-', '') # Remove UUID hyphens if present

        # Generate deterministic external ID using SecureIdentifier
        external_part = Familia.shorten_to_external_id(objid_hex, base: 36)

        # Get prefix from feature options, default to "ext"
        options = self.class.feature_options(:external_identifiers)
        prefix = options[:prefix] || "ext"

        "#{prefix}_#{external_part}"
      end

      def external_identifier
        extid
      end

      def init
        super if defined?(super)
        # External IDs are generated from objid, so no additional setup needed
      end

      Familia::Base.add_feature self, :external_identifiers, depends_on: [:object_identifiers]
    end
  end
end
