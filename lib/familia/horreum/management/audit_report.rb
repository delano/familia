# lib/familia/horreum/management/audit_report.rb
#
# frozen_string_literal: true

module Familia
  class Horreum
    # AuditReport wraps the results of a full health_check across all
    # consistency dimensions: instances timeline, unique indexes,
    # multi indexes, and participation collections.
    #
    # Created by ManagementMethods#health_check, consumed by repair methods.
    #
    AuditReport = Data.define(
      :model_class,        # String - class name that was audited
      :audited_at,         # Float - timestamp when audit started
      :instances,          # Hash {phantoms: [], missing: [], count_timeline: N, count_scan: N}
      :unique_indexes,     # Array<Hash> [{index_name:, stale: [], missing: []}]
      :multi_indexes,      # Array<Hash> [{index_name:, stale_members: [], orphaned_keys: []}]
      :participations,     # Array<Hash> [{collection_name:, stale_members: []}]
      # nil = not checked; [] = no fields; [{field_name:, klass:, orphaned_keys:, count:, status:}]
      :related_fields,
      :duration            # Float - seconds elapsed
    ) do
      # Returns true when every audit dimension is clean.
      #
      # Multi-indexes with status :not_implemented are skipped — they cannot
      # be assessed, so they neither pass nor fail the health check.
      # A nil related_fields means the dimension was not checked and does
      # not affect health.
      def healthy?
        instances[:phantoms].empty? &&
          instances[:missing].empty? &&
          unique_indexes.all? { |idx| idx[:stale].empty? && idx[:missing].empty? } &&
          multi_indexes.all? { |idx|
            next true if idx[:status] == :not_implemented

            idx[:stale_members].empty? && idx[:orphaned_keys].empty?
          } &&
          participations.all? { |p| p[:stale_members].empty? } &&
          related_fields_healthy?
      end

      # Returns true when every audit dimension was actually checked.
      #
      # A report can be healthy but incomplete when stub dimensions (like
      # multi-indexes) return :not_implemented, or when related_fields was
      # skipped (nil). This lets callers distinguish "everything checked
      # and clean" from "some dimensions were skipped".
      def complete?
        multi_indexes.none? { |idx| idx[:status] == :not_implemented } &&
          !related_fields.nil?
      end

      # Summary counts for quick inspection.
      def to_h
        hash = {
          model_class: model_class,
          audited_at: audited_at,
          healthy: healthy?,
          complete: complete?,
          duration: duration,
          instances: {
            count_timeline: instances[:count_timeline],
            count_scan: instances[:count_scan],
            phantoms: instances[:phantoms].size,
            missing: instances[:missing].size,
          },
          unique_indexes: unique_indexes.map { |idx|
            { index_name: idx[:index_name], stale: idx[:stale].size, missing: idx[:missing].size }
          },
          multi_indexes: multi_indexes.map { |idx|
            entry = { index_name: idx[:index_name], stale_members: idx[:stale_members].size, orphaned_keys: idx[:orphaned_keys].size }
            entry[:status] = idx[:status] if idx[:status]
            entry
          },
          participations: participations.map { |p|
            { collection_name: p[:collection_name], stale_members: p[:stale_members].size }
          },
        }

        hash[:related_fields] = related_fields_to_h
        hash
      end

      # Human-readable summary.
      def to_s
        lines = []
        lines << "AuditReport for #{model_class} (#{healthy? ? 'HEALTHY' : 'UNHEALTHY'})"
        lines << "  audited_at: #{Time.at(audited_at).utc} (#{duration.round(3)}s)"
        lines << "  instances: timeline=#{instances[:count_timeline]} scan=#{instances[:count_scan]}" \
                 " phantoms=#{instances[:phantoms].size} missing=#{instances[:missing].size}"

        unique_indexes.each do |idx|
          lines << "  unique_index :#{idx[:index_name]}: stale=#{idx[:stale].size} missing=#{idx[:missing].size}"
        end

        multi_indexes.each do |idx|
          if idx[:status] == :not_implemented
            lines << "  multi_index :#{idx[:index_name]}: not_implemented"
          else
            lines << "  multi_index :#{idx[:index_name]}: stale_members=#{idx[:stale_members].size}" \
                     " orphaned_keys=#{idx[:orphaned_keys].size}"
          end
        end

        participations.each do |p|
          lines << "  participation :#{p[:collection_name]}: stale_members=#{p[:stale_members].size}"
        end

        lines.concat(related_fields_lines)

        lines.join("\n")
      end

      private

      # A nil related_fields means the dimension was not checked, which
      # does not count against health. Otherwise every field must have
      # no orphaned_keys.
      def related_fields_healthy?
        return true if related_fields.nil?

        related_fields.all? { |rf| rf[:orphaned_keys].empty? }
      end

      # Renders the related_fields section of the to_s output.
      #
      # @return [Array<String>]
      def related_fields_lines
        return ['  related_fields: not_checked'] if related_fields.nil?

        related_fields.map do |rf|
          "  related_field :#{rf[:field_name]} (#{rf[:klass]}): " \
            "orphaned_keys=#{rf[:orphaned_keys].size}"
        end
      end

      # Renders the related_fields entry for the to_h output.
      #
      # @return [Array<Hash>, nil]
      def related_fields_to_h
        return nil if related_fields.nil?

        related_fields.map do |rf|
          {
            field_name: rf[:field_name],
            klass: rf[:klass],
            orphaned_keys: rf[:orphaned_keys].size,
            status: rf[:status],
          }
        end
      end
    end
  end
end
