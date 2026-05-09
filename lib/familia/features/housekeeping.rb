# lib/familia/features/housekeeping.rb
#
# frozen_string_literal: true

module Familia
  module Features
    # Housekeeping is a tiny DSL for registering named cleanup blocks (chores)
    # on a Horreum model class and running them against a single instance.
    #
    # The feature deliberately does *not* iterate, batch, aggregate stats, or
    # handle errors. Iteration strategy, scheduling, and error handling are
    # the consumer application's responsibility. This keeps the feature
    # focused: register a chore, run it against one record, return the
    # block's value.
    #
    # The name fits the Familia (household) theme: a chore is a small,
    # transient task. Run periodically then remove. For versioned, one-shot
    # transformations use +Familia::Migration+ instead.
    #
    # Example:
    #
    #   class Organization < Familia::Horreum
    #     feature :housekeeping
    #
    #     field :planid
    #
    #     chore :standardize_planid do |org|
    #       canonical = case org.planid
    #                   when "pro", "Pro", "professional_v1" then "professional"
    #                   when "free", "Free", "basic"          then "free"
    #                   end
    #       if canonical && canonical != org.planid
    #         org.planid = canonical
    #         org.save
    #         true
    #       end
    #     end
    #   end
    #
    #   org.tidy!
    #   # => { standardize_planid: true }   # block returned truthy
    #   # => { standardize_planid: nil }    # block returned nil/false
    #
    #   org.tidy!(:standardize_planid)
    #   # => { standardize_planid: true }
    #
    # Iteration is the caller's job, e.g. from a rake task or cron:
    #
    #   Organization.instances.each do |id|
    #     org = Organization.find_by_id(id) or next
    #     org.tidy!
    #   end
    #
    module Housekeeping
      Familia::Base.add_feature self, :housekeeping

      def self.included(base)
        Familia.trace(:LOADED, self, base) if Familia.debug?
        base.extend ModelClassMethods

        return if base.instance_variable_defined?(:@chores)

        base.instance_variable_set(:@chores, {})
      end

      # Familia::Features::Housekeeping::ModelClassMethods
      #
      module ModelClassMethods
        # Register a named chore block.
        #
        # @param name [Symbol, String] The chore name.
        # @yield [record] The block receives a model instance and may
        #   mutate/persist it. Its return value is passed back through
        #   {#tidy!}.
        # @return [Symbol] The registered name.
        # @raise [ArgumentError] If no block is given.
        def chore(name, &block)
          raise ArgumentError, 'chore requires a block' unless block

          (@chores ||= {})[name.to_sym] = block
          name.to_sym
        end

        # Returns a duped view of the registered chores.
        # @return [Hash{Symbol => Proc}]
        def chores
          (@chores ||= {}).dup
        end
      end

      # Run one or all registered chores against this instance.
      #
      # @param name [Symbol, String, nil] If given, run only the named chore.
      #   If nil, run all registered chores in registration order.
      # @return [Hash{Symbol => Object}] Map of chore name to the block's
      #   return value.
      # @raise [Familia::Problem] If +name+ is given but unregistered.
      def tidy!(name = nil)
        registry = self.class.instance_variable_get(:@chores) || {}

        to_run =
          if name
            sym = name.to_sym
            unless registry.key?(sym)
              raise Familia::Problem,
                    "Unknown chore: #{sym.inspect} for #{self.class} " \
                    "(registered: #{registry.keys.inspect})"
            end
            { sym => registry[sym] }
          else
            registry
          end

        to_run.each_with_object({}) do |(cname, block), out|
          out[cname] = block.call(self)
        end
      end
    end
  end
end
