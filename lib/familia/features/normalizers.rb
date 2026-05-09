# lib/familia/features/normalizers.rb
#
# frozen_string_literal: true

module Familia
  module Features
    # Normalizers is a lightweight, declarative DSL for registering temporary
    # data cleanup rules on Horreum model classes. These are distinct from
    # migrations: no versioning, no state tracking, no dry-run mode. Just
    # named lambdas that iterate over all instances of a model and normalize
    # field values.
    #
    # Use this when production data has accumulated inconsistencies (e.g. a
    # `planid` field stored variously as `"pro"`, `"Pro"`, `"professional"`,
    # `"professional_v1"`) and you want to run a cleanup rule for a few days
    # before removing the defensive code that handles the messy values.
    #
    # Example:
    #
    #   class Organization < Familia::Horreum
    #     feature :normalizers
    #
    #     field :planid
    #
    #     normalizer :standardize_planid do |org|
    #       canonical = case org.planid
    #                   when "pro", "Pro", "professional_v1" then "professional"
    #                   when "free", "Free", "basic"          then "free"
    #                   end
    #       if canonical && canonical != org.planid
    #         org.planid = canonical
    #         org.save
    #         true # signals "modified"
    #       end
    #     end
    #   end
    #
    #   Organization.normalize!
    #   # => { standardize_planid: { scanned: 4200, modified: 37, errors: 0, error_messages: [] } }
    #
    #   Organization.normalize!(:standardize_planid)
    #   # => { standardize_planid: { scanned: 4200, modified: 37, errors: 0, error_messages: [] } }
    #
    # Design constraints:
    #
    # * No implicit saves. The normalizer block is responsible for calling
    #   +save+ (or +commit_fields+, etc). The truthy return value of the
    #   block signals that the record was modified -- it does not trigger
    #   persistence.
    # * Batched iteration. Identifiers are pulled from the +instances+
    #   sorted set and processed in slices of +batch_size+ (default 100)
    #   so memory usage stays bounded.
    # * Error isolation. Individual record failures are caught, counted,
    #   and the first 10 messages collected. A single bad record will not
    #   abort the entire run.
    # * No ordering between normalizers. When +normalize!+ runs all
    #   registered normalizers, each one independently iterates the full
    #   set of instances. If order matters, use one normalizer with
    #   sequential steps internally.
    # * Idempotent by convention. Normalizers should be written so that
    #   running them twice produces the same result as running once. The
    #   conditional check pattern (`if canonical && canonical != org.planid`)
    #   is the expected idiom.
    #
    module Normalizers
      MAX_ERROR_MESSAGES = 10

      Familia::Base.add_feature self, :normalizers

      def self.included(base)
        Familia.trace(:LOADED, self, base) if Familia.debug?
        base.extend ModelClassMethods

        return if base.instance_variable_defined?(:@normalizers)

        base.instance_variable_set(:@normalizers, {})
      end

      # Familia::Features::Normalizers::ModelClassMethods
      #
      module ModelClassMethods
        # Register a named normalizer block.
        #
        # @param name [Symbol, String] The normalizer name (used in stats
        #   output and as the argument to +normalize!+ for selective runs).
        # @yield [record] The block receives a hydrated instance of the
        #   model class. Return a truthy value to signal that the record
        #   was modified; the block is responsible for persisting changes.
        # @return [Symbol] The registered name.
        # @raise [ArgumentError] If no block is given.
        #
        # @example
        #   normalizer :downcase_email do |user|
        #     if user.email && user.email != user.email.downcase
        #       user.email = user.email.downcase
        #       user.save
        #       true
        #     end
        #   end
        #
        def normalizer(name, &block)
          raise ArgumentError, 'Normalizer requires a block' unless block

          name = name.to_sym
          @normalizers ||= {}

          if @normalizers.key?(name)
            Familia.logger&.warn(
              "[normalizers] #{self}.normalizer(#{name.inspect}) overwriting existing definition"
            )
          end

          @normalizers[name] = block
          name
        end

        # Returns the registered normalizers for this class.
        #
        # @return [Hash{Symbol => Proc}] Frozen view of the normalizer map.
        #   The hash itself is duped so callers cannot mutate the registry.
        def normalizers
          (@normalizers ||= {}).dup
        end

        # Run one or all registered normalizers against every instance in
        # the +instances+ sorted set.
        #
        # @param name [Symbol, String, nil] If given, run only the named
        #   normalizer. If nil, run all registered normalizers.
        # @param batch_size [Integer] Number of identifiers to load and
        #   process per slice (default 100). Identifiers are still pulled
        #   from +instances+ in a single fetch, but records are loaded and
        #   processed in batches.
        # @return [Hash{Symbol => Hash}] Per-normalizer stats:
        #   { scanned:, modified:, errors:, error_messages: }.
        #   +error_messages+ holds at most {MAX_ERROR_MESSAGES} entries.
        # @raise [Familia::Problem] If +name+ is given but unregistered.
        #
        def normalize!(name = nil, batch_size: 100)
          registry = @normalizers ||= {}

          to_run =
            if name
              sym = name.to_sym
              unless registry.key?(sym)
                raise Familia::Problem,
                      "Unknown normalizer: #{sym.inspect} for #{self} " \
                      "(registered: #{registry.keys.inspect})"
              end
              { sym => registry[sym] }
            else
              registry
            end

          to_run.each_with_object({}) do |(nname, block), stats|
            stats[nname] = run_normalizer(nname, block, batch_size: batch_size)
          end
        end

        private

        def run_normalizer(name, block, batch_size:)
          scanned = 0
          modified = 0
          errors = 0
          error_messages = []

          Familia.logger&.info(
            "[normalize:#{self}.#{name}] starting batch_size=#{batch_size}"
          )

          identifiers = instances.members
          identifiers.each_slice(batch_size) do |batch|
            batch.each do |identifier|
              record = find_by_id(identifier)
              if record.nil?
                # Ghost entry: identifier in instances but no hash key.
                # Skip silently rather than counting as scanned/error;
                # cleanup is the caller's responsibility (see
                # cleanup_stale_instance_entry).
                next
              end

              scanned += 1
              begin
                modified += 1 if block.call(record)
              rescue StandardError => e
                errors += 1
                if error_messages.size < MAX_ERROR_MESSAGES
                  error_messages << "#{identifier}: #{e.class}: #{e.message}"
                end
                Familia.logger&.warn(
                  "[normalize:#{self}.#{name}] error for #{identifier}: " \
                  "#{e.class}: #{e.message}"
                )
              end
            end
          end

          Familia.logger&.info(
            "[normalize:#{self}.#{name}] done scanned=#{scanned} " \
            "modified=#{modified} errors=#{errors}"
          )

          {
            scanned: scanned,
            modified: modified,
            errors: errors,
            error_messages: error_messages,
          }
        end
      end
    end
  end
end
