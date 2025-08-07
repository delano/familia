# lib/familia/features/transient_fields.rb

module Familia
  module Features
    # Famnilia::Features::TransientFields
    #
    module TransientFields
      def self.included(base)
        Familia.ld "[#{base}] Loaded #{self}"
        base.extend ClassMethods
      end

      # ClassMethods
      #
      module ClassMethods
        def transient_field(name, as: name, **)
          # Force specific options
          field name, as: as, fast_method: false, on_conflict: :raise, category: :transient, **opts

          define_method "#{name}=" do |value|
            super(RedactedString.new(value))
          end
        end
      end
      extend ClassMethods

      Familia::Base.add_feature self, :transient_fields, depends_on: nil
    end
  end
end
