# lib/familia/features/relationships/indexing/record_key_ownership.rb
#
# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      module Indexing
        # Decides which record a key belongs to when several records of one
        # Horreum class can claim it.
        #
        # Record keys are "<prefix><delim><identifier><delim><name>", and an
        # identifier may itself contain the delimiter. So one key can parse
        # as keys of several records, and a key under the bucket prefix of a
        # multi_index can be another record's set field or bucket. The
        # multi_index rebuild and audit use this module so that they leave
        # such a key to the record it belongs to.
        module RecordKeyOwnership
          module_function

          # Returns the hash key of the existing record, other than +owner+,
          # that .other_record_key assigns +key+ to, or nil when there is
          # none.
          #
          # @param key [String] a key under +owner+'s bucket prefix
          # @param owner [Familia::Horreum, Class] the scope instance, or the
          #   indexed class for a class-level index
          # @param names [Hash] .record_set_key_names of +owner+'s class,
          #   passed by callers that check many keys
          # @return [String, nil]
          def other_record_key_owner(key, owner, names: nil)
            owner_class = owner_class_of(owner)
            own_identifier = owner.is_a?(Class) ? nil : owner.identifier
            identifier, = other_record_key(key, owner_class, own_identifier, names: names)
            identifier && owner_class.dbkey(identifier)
          end

          # Returns [identifier, name] when +key+ is the key +name+ of an
          # existing record of +owner_class+ whose identifier is longer than
          # +own_identifier+, or nil when there is none.
          #
          # Record keys are "<prefix><delim><identifier><delim><name>", and
          # an identifier may itself contain the delimiter. So one key can
          # parse as keys of several records. With records "c-9" and
          # "c-9:dept_index", the key "company:c-9:dept_index:tags" is both
          # a dept_index bucket of "c-9" and the +tags+ set of
          # "c-9:dept_index". This method tries every split of +key+ at a
          # delimiter. A split names a record when the part after it is the
          # name of a set field of the class or the bucket of an
          # instance-scoped multi_index within the class, and a record with
          # the identifier before it exists.
          #
          # Such a key is assigned to the existing record with the longest
          # identifier. A class-level bucket has no identifier, so any
          # existing record wins over it. The rule gives each key one owner,
          # so the rebuilds of two scopes whose keys overlap do not both
          # clear it, and the audit reads it for the scope whose rebuild
          # clears it. The doc of Familia::Horreum.extract_identifier_from_key
          # says "This is safe for compound identifiers that contain the
          # delimiter character". This module assumes that a field value
          # holding the delimiter followed by an index name is rarer than
          # such an identifier, so it prefers the longest identifier.
          #
          # @param key [String] a key under +owner_class+'s record prefix
          # @param owner_class [Class] the Horreum class of the records
          # @param own_identifier [String, nil] identifier of the record the
          #   key is checked for, or nil for a class-level bucket
          # @param names [Hash] .record_set_key_names of +owner_class+
          # @return [Array(String, String), nil]
          def other_record_key(key, owner_class, own_identifier, names: nil)
            record_prefix = Familia.join(owner_class.prefix, '').b
            bkey = key.b
            return nil unless bkey.start_with?(record_prefix)

            delim = Familia.delim.to_s.b
            own_size = own_identifier.to_s.bytesize
            names ||= record_set_key_names(owner_class)
            splits = []
            each_delimiter_split(bkey.byteslice(record_prefix.bytesize..), delim) do |identifier, name|
              splits << [identifier, name] if identifier.bytesize > own_size && record_set_key_name?(name, names, delim)
            end
            splits.reverse_each do |identifier, name|
              identifier = identifier.force_encoding(key.encoding)
              return [identifier, name.force_encoding(key.encoding)] if owner_class.exists?(identifier)
            end
            nil
          end

          # Yields each split of the binary string +text+ at an occurrence
          # of +delim+, as the part before it and the part after it.
          def each_delimiter_split(text, delim)
            position = 0
            while (split_at = text.index(delim, position))
              yield text.byteslice(0, split_at), text.byteslice((split_at + delim.bytesize)..)
              position = split_at + 1
            end
          end

          # Returns the Horreum class whose records share key space with the
          # buckets of +owner+: the scope class, or the indexed class itself
          # for a class-level index.
          def owner_class_of(owner)
            owner.is_a?(Class) ? owner : owner.class
          end

          # Names that follow "<prefix><delim><identifier><delim>" in the
          # keys of a record of +owner_class+ that hold a set: the related
          # set fields, and the instance-scoped multi_index names whose
          # buckets live under the record.
          #
          # @param owner [Familia::Horreum, Class] a record, or its class
          # @return [Hash{Symbol => Array<String>}] :fields and :indexes, as
          #   binary strings
          def record_set_key_names(owner)
            owner_class = owner_class_of(owner)
            fields = owner_class.related_fields.each_value.filter_map do |definition|
              next if definition.opts[:dbkey]
              next unless definition.klass.is_a?(Class) && definition.klass <= Familia::UnsortedSet

              definition.name.to_s.b
            end
            indexes = Familia.multi_indexes(class_level: false).filter_map do |descriptor|
              descriptor.index_name.to_s.b if descriptor.scope_class == owner_class
            end
            { fields: fields, indexes: indexes }
          end

          # Whether +name+ is a set key name from .record_set_key_names: a
          # set field's name, an index name (the bucket of a blank value) or
          # an index name followed by the delimiter and a value.
          def record_set_key_name?(name, names, delim)
            return true if names[:fields].include?(name)

            names[:indexes].any? { |index| name == index || name.start_with?(index + delim) }
          end
        end
      end
    end
  end
end
