# lib/familia/features/housekeeping/enforce_collection_caps.rb
#
# frozen_string_literal: true

module Familia
  module Features
    module Housekeeping
      # A reusable, idempotent chore that trims every capped collection on an
      # instance down to its :max_length via +enforce_max_length!+.
      #
      # Adding max_length: to a live collection caps future writes but leaves
      # any existing overage in place until the next write. Register this chore
      # and run it (once, or nightly until clean) to trim the backlog. A
      # collection already within its cap trims zero members, so the chore
      # returns the removed count on the first pass and nil on every clean
      # pass after -- the truthy-modified / nil-no-op convention run_chores!
      # aggregates on.
      #
      # The class itself responds to +call+, so it registers directly:
      #
      #   class Customer < Familia::Horreum
      #     feature :housekeeping
      #
      #     sorted_set :events,       max_length: 100
      #     list       :activity_log, max_length: 50
      #
      #     chore :enforce_collection_caps, Familia::Features::Housekeeping::EnforceCollectionCaps
      #   end
      #
      # It is also a base class. Capped lists have per-end semantics the sweep
      # cannot infer (push-fed lists keep the tail, unshift-fed ones the head),
      # so subclass and override +keep_for+ when a list is unshift-fed; override
      # +collection_names+ to scope the sweep:
      #
      #   class InboxCaps < Familia::Features::Housekeeping::EnforceCollectionCaps
      #     def keep_for(name)
      #       name == :inbox ? :head : :tail
      #     end
      #   end
      #
      class EnforceCollectionCaps
        # Entry point when the class itself is registered as the chore.
        #
        # @param obj [Familia::Horreum] the instance under housekeeping
        # @return [Integer, nil] members removed, or nil when nothing trimmed
        def self.call(obj)
          new.call(obj)
        end

        # @param obj [Familia::Horreum] the instance under housekeeping
        # @return [Integer, nil] members removed, or nil when nothing trimmed
        def call(obj)
          removed = capped_collections(obj).sum do |name, collection|
            enforce(name, collection)
          end
          removed if removed.positive?
        end

        protected

        # The (name, collection) pairs the sweep trims: every candidate from
        # +collection_names+ that carries a :max_length. Uncapped collections
        # and non-capping types report a nil max_length and drop out here, so
        # the sweep never trips enforce_max_length!'s uncapped guard.
        def capped_collections(obj)
          collection_names(obj).filter_map do |name|
            collection = obj.send(name)
            [name, collection] if collection.max_length
          end
        end

        # Candidate collection names; override to scope the sweep.
        def collection_names(obj)
          obj.class.related_fields.keys
        end

        def enforce(name, collection)
          case collection
          when Familia::ListKey
            collection.enforce_max_length!(keep: keep_for(name))
          else
            collection.enforce_max_length!
          end
        end

        # Which end of a capped list survives; override per list name for
        # unshift-fed lists. The default matches push-fed lists.
        def keep_for(_name)
          :tail
        end
      end
    end
  end
end
