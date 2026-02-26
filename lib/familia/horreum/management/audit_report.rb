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
      :duration            # Float - seconds elapsed
    ) do
      # Returns true when every audit dimension is clean.
      def healthy?
        instances[:phantoms].empty? &&
          instances[:missing].empty? &&
          unique_indexes.all? { |idx| idx[:stale].empty? && idx[:missing].empty? } &&
          multi_indexes.all? { |idx| idx[:stale_members].empty? && idx[:orphaned_keys].empty? } &&
          participations.all? { |p| p[:stale_members].empty? }
      end

      # Summary counts for quick inspection.
      def to_h
        {
          model_class: model_class,
          audited_at: audited_at,
          healthy: healthy?,
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
            { index_name: idx[:index_name], stale_members: idx[:stale_members].size, orphaned_keys: idx[:orphaned_keys].size }
          },
          participations: participations.map { |p|
            { collection_name: p[:collection_name], stale_members: p[:stale_members].size }
          },
        }
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
          lines << "  multi_index :#{idx[:index_name]}: stale_members=#{idx[:stale_members].size}" \
                   " orphaned_keys=#{idx[:orphaned_keys].size}"
        end

        participations.each do |p|
          lines << "  participation :#{p[:collection_name]}: stale_members=#{p[:stale_members].size}"
        end

        lines.join("\n")
      end
    end
  end
end
