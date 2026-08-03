# lib/familia/features/housekeeping.rb
#
# frozen_string_literal: true

require_relative 'housekeeping/enforce_collection_caps'

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

      # Default Redis-pipelined batch size for `run_chores!`. Each batch hits
      # Redis once via `load_multi`, then drives the chore block per record.
      # 100 trades pipeline efficiency against per-batch latency.
      DEFAULT_BATCH_SIZE = 100

      def self.included(base)
        Familia.trace :LOADED, self, base if Familia.debug?
        base.extend ModelClassMethods
        base.include ModelInstanceMethods
      end

      # Housekeeping::ModelClassMethods
      module ModelClassMethods
        # Register a chore by name. Takes either a block or any callable
        # (a class or object responding to +call+) -- both receive the
        # instance. Callables allow shipping reusable chores as classes,
        # e.g. Housekeeping::EnforceCollectionCaps.
        #
        # @param name [Symbol, String] chore identifier
        # @param callable [#call, nil] callable invoked with the instance
        # @yield [obj] block invoked with the instance during do_chore!/do_chores!
        # @return [#call] the registered handler
        # @raise [ArgumentError] if name is blank, neither or both of
        #   callable/block are given, or the callable does not respond to call
        def chore(name, callable = nil, &block)
          raise ArgumentError, 'chore name required' if name.nil? || name.to_s.empty?
          raise ArgumentError, "chore #{name.inspect} takes a callable or a block, not both" if callable && block

          handler = callable || block
          raise ArgumentError, "chore #{name.inspect} requires a callable or block" unless handler
          raise ArgumentError, "chore #{name.inspect} callable must respond to #call" unless handler.respond_to?(:call)

          chores[name.to_sym] = handler
        end

        # Registered chores in registration order. Subclasses inherit a copy
        # of their parent's chores on first access, so registering a new chore
        # on a subclass does not mutate the parent.
        #
        # @return [Hash{Symbol => #call}]
        def chores
          @chores ||= if superclass.respond_to?(:chores)
            superclass.chores.dup
          else
            {}
          end
        end

        # Run registered chores against every record reachable via the
        # `instances` class-level sorted set. Records are loaded in pipelined
        # batches (`load_multi`) and each chore is executed per record with
        # error isolation -- one failing chore call does not abort the run.
        #
        # Stats shape:
        #
        #   {
        #     model: 'User',
        #     scanned: 4200,
        #     chores: {
        #       downcase_email: { modified: 37, errors: 0 },
        #       default_timezone: { modified: 102, errors: 1 },
        #     },
        #   }
        #
        # The `modified` counter increments when the chore block returns a
        # truthy value (the conventional "modified" signal). The `errors`
        # counter increments when the chore block raises; the exception is
        # logged via `Familia.warn` and iteration continues.
        #
        # Requires the class to expose an `instances` collection (Horreum's
        # default class-level sorted set) and `load_multi` (Horreum default).
        #
        # @param chore_name [Symbol, String, nil] specific chore to run; nil
        #   runs every registered chore against each record
        # @param limit [Integer, nil] cap on records scanned; nil iterates all
        # @param batch_size [Integer] pipeline batch size for `load_multi`
        # @return [Hash] stats hash (see above)
        # @raise [ArgumentError] if the class has no chores, the named chore
        #   is not registered, or `instances`/`load_multi` are unavailable
        def run_chores!(chore_name: nil, limit: nil, batch_size: DEFAULT_BATCH_SIZE)
          unless respond_to?(:instances) && respond_to?(:load_multi)
            raise ArgumentError, "#{name} cannot run_chores! without instances and load_multi"
          end

          chore_keys = resolve_chore_keys(chore_name)
          stats      = chore_keys.to_h { |key| [key, { modified: 0, errors: 0 }] }
          scanned    = 0

          instances.to_a.each_slice(batch_size) do |batch_ids|
            break if limit && scanned >= limit

            batch_ids = batch_ids.take(limit - scanned) if limit
            records   = load_multi(batch_ids).compact
            records.each do |record|
              scanned += 1
              chore_keys.each do |key|
                begin
                  stats[key][:modified] += 1 if record.do_chore!(key)
                rescue StandardError => e
                  stats[key][:errors] += 1
                  Familia.warn "[run_chores!] #{name}##{record.identifier} chore=#{key} failed: #{e.message}"
                end
              end
            end
          end

          { model: name, scanned: scanned, chores: stats }
        end

        private

        def resolve_chore_keys(chore_name)
          raise ArgumentError, "#{name} has no chores registered" if chores.empty?

          if chore_name
            key = chore_name.to_sym
            raise ArgumentError, "unknown chore #{chore_name.inspect}" unless chores.key?(key)

            [key]
          else
            chores.keys
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
          self.class.chores.each_with_object({}) do |(chore_name, handler), results|
            results[chore_name] = handler.call(self)
          end
        end

        alias tidy! do_chores!
      end
    end
  end
end
