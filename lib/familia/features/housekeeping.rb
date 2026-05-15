# lib/familia/features/housekeeping.rb
#
# frozen_string_literal: true

module Familia
  module Features
    # Housekeeping registers named cleanup chores on a Horreum class and runs
    # them against a single instance. It is intended for short-lived, repeated
    # tidying of fields whose values have drifted (e.g. running nightly for a
    # few days, then removing the chore once data is clean).
    #
    # The feature owns registration and per-instance execution only. Iteration,
    # batching, scheduling, error aggregation, and persistence are the caller's
    # responsibility.
    #
    # Example:
    #
    #   class Organization < Familia::Horreum
    #     feature :housekeeping
    #     field :planid
    #
    #     chore :standardize_planid do |org|
    #       canonical = case org.planid
    #                   when 'pro', 'Pro', 'professional_v1' then 'professional'
    #                   when 'free', 'Free', 'basic'         then 'free'
    #                   end
    #       if canonical && canonical != org.planid
    #         org.planid = canonical
    #         org.save
    #         true
    #       end
    #     end
    #   end
    #
    #   org = Organization.from_identifier('acme-corp')
    #   org.do_chores!
    #   # => { standardize_planid: true }
    #
    #   org.do_chore!(:standardize_planid)
    #   # => true
    #
    #   org.tidy! # alias for do_chores!
    #   # => { standardize_planid: true }
    #
    # See docs/guides/feature-housekeeping.md for the full guide.
    module Housekeeping
      Familia::Base.add_feature self, :housekeeping

      def self.included(base)
        Familia.trace :LOADED, self, base if Familia.debug?
        base.extend ModelClassMethods
        base.include ModelInstanceMethods
      end

      # Housekeeping::ModelClassMethods
      module ModelClassMethods
        # Register a chore by name. The block receives the instance.
        #
        # @param name [Symbol, String] chore identifier
        # @yield [obj] block invoked with the instance during do_chore!/do_chores!
        # @return [Proc] the registered block
        # @raise [ArgumentError] if name is blank or no block is given
        def chore(name, &block)
          raise ArgumentError, 'chore name required' if name.nil? || name.to_s.empty?
          raise ArgumentError, "chore #{name.inspect} requires a block" unless block

          chores[name.to_sym] = block
        end

        # Registered chores in registration order. Subclasses inherit a copy
        # of their parent's chores on first access, so registering a new chore
        # on a subclass does not mutate the parent.
        #
        # @return [Hash{Symbol => Proc}]
        def chores
          @chores ||= if superclass.respond_to?(:chores)
            superclass.chores.dup
          else
            {}
          end
        end
      end

      # Housekeeping::ModelInstanceMethods
      module ModelInstanceMethods
        # Run a single registered chore by name.
        #
        # @param name [Symbol, String] chore to run
        # @return [Object] the block's return value
        # @raise [ArgumentError] if name is blank or not registered
        def do_chore!(name)
          raise ArgumentError, 'chore name required' if name.nil? || name.to_s.empty?

          key = name.to_sym
          registered = self.class.chores
          raise ArgumentError, "unknown chore #{name.inspect}" unless registered.key?(key)

          registered[key].call(self)
        end

        # Run every registered chore against this instance.
        #
        # @return [Hash{Symbol => Object}] chore name => block return value
        def do_chores!
          self.class.chores.each_with_object({}) do |(chore_name, block), results|
            results[chore_name] = block.call(self)
          end
        end

        alias tidy! do_chores!
      end
    end
  end
end
