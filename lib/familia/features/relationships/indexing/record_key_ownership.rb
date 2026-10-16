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
        #
        # A record exists when its hash key holds a hash (see
        # .existing_records). The methods that take a list of keys check
        # the candidate records of their keys in pipelines that each hold
        # at most MAX_CANDIDATE_BATCH_BYTES of identifiers, and a key with
        # no candidate costs no command.
        module RecordKeyOwnership
          module_function

          # The most candidate records checked for one key.
          #
          # A candidate is a split of the key at a delimiter where the part
          # after it is a set key name (see .candidate_split_offsets). An
          # ordinary key has none. A key has one for each record whose
          # identifier is a prefix of the key followed by such a name, and
          # records nest like that rarely more than once or twice. A field
          # value can repeat "<delim><index>" any number of times, though,
          # and each candidate costs a copy of its identifier (up to the
          # length of the key) and a TYPE command. This cap bounds the work
          # for one key at that many copies and commands. A key with more
          # candidates gets TOO_MANY_CANDIDATES instead of an owner.
          MAX_CANDIDATE_SPLITS = 8

          # Returned in place of an owner for a key with more than
          # MAX_CANDIDATE_SPLITS candidates, whose owner is not checked. The
          # multi_index rebuild raises Familia::IndexBucketConflictError
          # with this reason for such a key, and the multi_index audit
          # reports it.
          TOO_MANY_CANDIDATES = :too_many_candidate_owners

          # The most bytes of record identifiers checked in one pipeline.
          #
          # MAX_CANDIDATE_SPLITS bounds the candidates of one key, but the
          # rebuild and audits pass keys in slices, and each candidate
          # identifier can be as long as its key. The candidates of the
          # keys in a slice are therefore checked in groups: a group is
          # sent once adding the next key's candidates would pass this many
          # bytes. .existing_records splits the identifiers of a group the
          # same way, so an identifier longer than this is checked in a
          # pipeline of its own.
          MAX_CANDIDATE_BATCH_BYTES = 1_048_576

          # Returns, for each of +identifiers+, whether a record of
          # +owner_class+ with that identifier exists: whether its hash key
          # holds a hash (Familia::Horreum::OBJECT_KEY_TYPE).
          #
          # EXISTS is not enough. A multi_index bucket whose field value
          # equals the class suffix sits at the hash key of a record named
          # after the index: the bucket "customer:role_index:object" is a
          # set, and no record "role_index" exists.
          #
          # The TYPE commands go out in pipelines of at most
          # MAX_CANDIDATE_BATCH_BYTES of identifiers each (one identifier
          # longer than that gets a pipeline of its own). The hash keys are
          # built from bytes, so an identifier with invalid UTF-8 does not
          # raise Encoding::CompatibilityError against a prefix with
          # non-ASCII characters.
          #
          # @param owner_class [Class] the Horreum class of the records
          # @param identifiers [Array<String>] record identifiers
          # @return [Array<Boolean>] one flag per identifier, in order
          def existing_records(owner_class, identifiers)
            flags = []
            byte_bounded_groups(identifiers) { |identifier| identifier.to_s.bytesize }.each do |group|
              types = owner_class.dbclient.pipelined do |pipe|
                group.each { |identifier| pipe.type(record_hash_key(owner_class, identifier)) }
              end
              flags.concat(types.map { |type| type == Familia::Horreum::OBJECT_KEY_TYPE })
            end
            flags
          end

          # Splits +items+ into consecutive groups whose sizes, as the block
          # returns them, add up to at most MAX_CANDIDATE_BATCH_BYTES. An
          # item larger than that forms a group of its own.
          #
          # @param items [Array]
          # @yieldparam item [Object]
          # @yieldreturn [Integer] the size of +item+ in bytes
          # @return [Array<Array>]
          def byte_bounded_groups(items)
            groups = []
            group_bytes = 0
            items.each do |item|
              bytes = yield(item)
              if groups.empty? || group_bytes + bytes > MAX_CANDIDATE_BATCH_BYTES
                groups << []
                group_bytes = 0
              end
              groups.last << item
              group_bytes += bytes
            end
            groups
          end

          # Returns the hash key of the record of +owner_class+ with
          # +identifier+, as a binary String built from the bytes of its
          # parts.
          #
          # @param owner_class [Class]
          # @param identifier [String]
          # @return [String]
          def record_hash_key(owner_class, identifier)
            record_prefix(owner_class) << identifier.to_s.b << Familia.delim.to_s.b << owner_class.suffix.to_s.b
          end

          # Returns the hash key of the existing record, other than +owner+,
          # that .other_record_key assigns +key+ to, nil when there is none,
          # or TOO_MANY_CANDIDATES.
          #
          # @param key [String] a key under +owner+'s bucket prefix
          # @param owner [Familia::Horreum, Class] the scope instance, or the
          #   indexed class for a class-level index
          # @param names [Hash] .record_set_key_names of +owner+'s class,
          #   passed by callers that check many keys
          # @return [String, Symbol, nil]
          def other_record_key_owner(key, owner, names: nil)
            other_record_key_owners([key], owner, names: names).first
          end

          # .other_record_key_owner for each of +keys+. The candidates are
          # checked in pipelines of at most MAX_CANDIDATE_BATCH_BYTES (see
          # .resolve_candidates).
          #
          # @param keys [Array<String>]
          # @param owner [Familia::Horreum, Class]
          # @param names [Hash, nil]
          # @return [Array<String, Symbol, nil>] one entry per key, in order
          def other_record_key_owners(keys, owner, names: nil)
            owner_class = owner_class_of(owner)
            own_identifier = owner.is_a?(Class) ? nil : owner.identifier
            records = other_record_keys(keys, owner_class, Array.new(keys.size, own_identifier), names: names)
            keys.zip(records).map do |key, record|
              next record unless record.is_a?(Array)

              record_hash_key(owner_class, record.first).force_encoding(key.encoding)
            end
          end

          # Returns [identifier, name] when +key+ is the key +name+ of an
          # existing record of +owner_class+ whose identifier is longer than
          # +own_identifier+, nil when there is none, or
          # TOO_MANY_CANDIDATES.
          #
          # Record keys are "<prefix><delim><identifier><delim><name>", and
          # an identifier may itself contain the delimiter. So one key can
          # parse as keys of several records. With records "c-9" and
          # "c-9:dept_index", the key "company:c-9:dept_index:tags" is both
          # a dept_index bucket of "c-9" and the +tags+ set of
          # "c-9:dept_index". A split of +key+ at a delimiter names a record
          # when the part after it is the name of a set field of the class
          # or the bucket of an instance-scoped multi_index within the
          # class, and a record with the identifier before it exists (see
          # .existing_records).
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
          # @return [Array(String, String), Symbol, nil]
          def other_record_key(key, owner_class, own_identifier, names: nil)
            other_record_keys([key], owner_class, [own_identifier], names: names).first
          end

          # .other_record_key for each of +keys+, with the matching entry of
          # +own_identifiers+. The candidates are checked in pipelines of
          # at most MAX_CANDIDATE_BATCH_BYTES (see .resolve_candidates).
          #
          # @param keys [Array<String>]
          # @param owner_class [Class]
          # @param own_identifiers [Array<String, nil>] one per key
          # @param names [Hash, nil]
          # @return [Array<Array(String, String), Symbol, nil>] one entry per
          #   key, in order
          def other_record_keys(keys, owner_class, own_identifiers, names: nil)
            names ||= record_set_key_names(owner_class)
            delim = Familia.delim.to_s.b
            prefix = record_prefix(owner_class)
            resolve_candidates(owner_class, keys, prefix.bytesize, delim) do |key, idx|
              rest = bytes_after_prefix(key, prefix)
              next nil unless rest

              candidate_split_offsets(rest, delim, names, own_identifiers[idx].to_s.bytesize)
            end
          end

          # Returns the owner of +key+ when it is a multi_index bucket under
          # the record prefix of +owner_class+, nil when it is not, or
          # TOO_MANY_CANDIDATES.
          #
          # The owner is +owner_class+ for a bucket of a class-level
          # multi_index declared on +owner_class+
          # ("<prefix><delim><index><delim><value>"). For a bucket of an
          # instance-scoped multi_index within +owner_class+
          # ("<prefix><delim><scope id><delim><index><delim><value>") it is
          # the scope identifier, and only when a record with that
          # identifier exists. When several splits of +key+ name existing
          # scopes, the longest identifier wins, as in .other_record_key.
          #
          # The audits of related fields and participation collections
          # match "<prefix><delim>*<delim><name>" and read the part the
          # wildcard matched as a record identifier. A field value equal to
          # <name> puts a bucket in that pattern, so they call this method
          # to leave such a key to the index it belongs to. The multi_index
          # audit and repair own buckets.
          #
          # @param key [String] a key returned by SCAN
          # @param owner_class [Class] the Horreum class whose record prefix
          #   the key starts with
          # @param names [Hash] .record_set_key_names of +owner_class+,
          #   passed by callers that check many keys
          # @return [Class, String, Symbol, nil]
          def index_bucket_owner(key, owner_class, names: nil)
            index_bucket_owners([key], owner_class, names: names).first
          end

          # .index_bucket_owner for each of +keys+. The candidate scopes are
          # checked in pipelines of at most MAX_CANDIDATE_BATCH_BYTES (see
          # .resolve_candidates).
          #
          # @param keys [Array<String>]
          # @param owner_class [Class]
          # @param names [Hash, nil]
          # @return [Array<Class, String, Symbol, nil>] one entry per key, in
          #   order
          def index_bucket_owners(keys, owner_class, names: nil)
            names ||= record_set_key_names(owner_class)
            delim = Familia.delim.to_s.b
            prefix = record_prefix(owner_class)
            class_level = class_level_index_names(owner_class)
            # Only index names make a split a candidate here. The question
            # is whether the key is a bucket, and a set field of a scope
            # record is that record's own key, not a bucket of any index.
            bucket_names = { fields: [], indexes: names[:indexes] }
            owners = Array.new(keys.size)
            scopes = resolve_candidates(owner_class, keys, prefix.bytesize, delim) do |key, idx|
              rest = bytes_after_prefix(key, prefix)
              next nil unless rest

              if class_level.any? { |index| rest.start_with?(index + delim) }
                owners[idx] = owner_class
                next nil
              end
              candidate_split_offsets(rest, delim, bucket_names, 0)
            end
            owners.each_with_index.map do |owner, idx|
              next owner if owner

              scope = scopes[idx]
              scope.is_a?(Array) ? scope.first : scope
            end
          end

          # Whether +key+ is "<prefix><delim><index><delim><value>" for a
          # class-level multi_index <index> declared on +owner_class+. Only
          # the key's shape is checked, so the key may also be a key of a
          # record whose identifier starts with "<index><delim>".
          #
          # @param key [String]
          # @param owner_class [Class]
          # @return [Boolean]
          def class_level_bucket?(key, owner_class)
            rest = key_after_record_prefix(key, owner_class)
            return false unless rest

            delim = Familia.delim.to_s.b
            class_level_index_names(owner_class).any? { |index| rest.start_with?(index + delim) }
          end

          # Returns the bytes of +key+ after "<prefix><delim>" of
          # +owner_class+, or nil when +key+ does not start with them.
          def key_after_record_prefix(key, owner_class)
            bytes_after_prefix(key, record_prefix(owner_class))
          end

          # Returns "<prefix><delim>" of +owner_class+ as a new binary
          # String.
          def record_prefix(owner_class)
            Familia.join(owner_class.prefix, '').b
          end

          # Returns the bytes of +key+ after the binary +prefix+, or nil when
          # +key+ does not start with it.
          def bytes_after_prefix(key, prefix)
            bkey = key.b
            return nil unless bkey.start_with?(prefix)

            bkey.byteslice(prefix.bytesize..)
          end

          # Names of the class-level multi_indexes declared on
          # +owner_class+, whose buckets live under its record prefix, as
          # binary strings.
          #
          # @param owner_class [Class]
          # @return [Array<String>]
          def class_level_index_names(owner_class)
            Familia.multi_indexes(class_level: true, owner: owner_class).map do |descriptor|
              descriptor.index_name.to_s.b
            end
          end

          # Returns the splits of the binary string +rest+ (a key without
          # the record prefix) whose identifier is longer than
          # +longer_than+ bytes and whose name is a set key name from
          # +names+ (see .record_set_key_names): a set field's name that
          # ends the key, or an index name followed by the delimiter and a
          # value (a bucket). A split is the offset of its delimiter in
          # +rest+, which is also the length of its identifier, and the
          # offsets are in increasing order. Returns TOO_MANY_CANDIDATES
          # when there are more than MAX_CANDIDATE_SPLITS.
          #
          # An index name that ends the key makes no candidate. That is the
          # key the factories name for a blank value (see
          # MultiIndexGenerators.bucket_key_prefix), which is not index data
          # and which no multi_index method reads or writes. When it is a
          # related field of the same name, the field names already make it
          # a candidate.
          #
          # The walk copies no part of +rest+. A set field name must be the
          # whole rest of the key, so each field is compared at the one
          # offset where it would start. An index name is searched for with
          # String#index.
          def candidate_split_offsets(rest, delim, names, longer_than)
            offsets = field_split_offsets(rest, delim, names[:fields], longer_than)
            return TOO_MANY_CANDIDATES unless index_split_offsets(rest, delim, names[:indexes], longer_than, offsets)

            offsets.sort
          end

          # Offsets in +rest+ of the delimiter before a set field name that
          # ends the key, after +longer_than+ bytes.
          def field_split_offsets(rest, delim, fields, longer_than)
            fields.filter_map do |field|
              split_at = rest.bytesize - field.bytesize - delim.bytesize
              split_at if split_at > longer_than &&
                          rest.byteslice(split_at, delim.bytesize + field.bytesize) == delim + field
            end.uniq
          end

          # Adds to +offsets+ the offsets in +rest+ of the delimiter before
          # an index name that is followed by the delimiter, after
          # +longer_than+ bytes. Returns false as soon as +offsets+ holds
          # more than MAX_CANDIDATE_SPLITS, true otherwise.
          def index_split_offsets(rest, delim, indexes, longer_than, offsets)
            indexes.each do |index|
              needle = delim + index
              position = longer_than + 1
              while (split_at = rest.index(needle, position))
                after = split_at + needle.bytesize
                if rest.byteslice(after, delim.bytesize) == delim && !offsets.include?(split_at)
                  offsets << split_at
                  return false if offsets.size > MAX_CANDIDATE_SPLITS
                end
                position = split_at + 1
              end
            end
            offsets.size <= MAX_CANDIDATE_SPLITS
          end

          # Resolves the candidate splits of each of +keys+ to the one with
          # the longest identifier of an existing record. The block returns
          # the offsets of a key's candidate splits in the part of the key
          # after its first +prefix_bytes+ bytes (see
          # .candidate_split_offsets), TOO_MANY_CANDIDATES, or nil for a key
          # that is not under the prefix.
          #
          # The block runs for one key at a time, and only the offsets are
          # kept. The identifiers are copied out of the key when their
          # group is checked. A group is checked once adding the next key's
          # candidates would pass MAX_CANDIDATE_BATCH_BYTES of identifiers,
          # so the copies and the pipeline for one group stay within that
          # many bytes, or within one key's candidates when they alone pass
          # it. The identifier and name are returned in the encoding of the
          # key.
          #
          # @param prefix_bytes [Integer] bytesize of the record prefix
          # @yieldparam key [String]
          # @yieldparam idx [Integer]
          # @yieldreturn [Array<Integer>, Symbol, nil]
          # @return [Array<Array(String, String), Symbol, nil>]
          def resolve_candidates(owner_class, keys, prefix_bytes, delim)
            results = Array.new(keys.size)
            pending = []
            pending_bytes = 0
            keys.each_with_index do |key, idx|
              offsets = yield(key, idx)
              next results[idx] = offsets if offsets == TOO_MANY_CANDIDATES
              next if offsets.nil? || offsets.empty?

              bytes = offsets.sum
              if !pending.empty? && pending_bytes + bytes > MAX_CANDIDATE_BATCH_BYTES
                resolve_pending_candidates(owner_class, pending, prefix_bytes, delim, results)
                pending_bytes = 0
              end
              pending << [idx, key, offsets]
              pending_bytes += bytes
            end
            resolve_pending_candidates(owner_class, pending, prefix_bytes, delim, results) unless pending.empty?
            results
          end

          # Checks the candidates of the +pending+ [idx, key, offsets]
          # entries with one call to .existing_records, stores each key's
          # [identifier, name] or nil in +results+, and empties +pending+.
          # The identifier and name are byte slices of the key, in its
          # encoding.
          def resolve_pending_candidates(owner_class, pending, prefix_bytes, delim, results)
            identifiers = pending.flat_map do |(_idx, key, offsets)|
              offsets.map { |split_at| key.byteslice(prefix_bytes, split_at) }
            end
            flags = existing_records(owner_class, identifiers)
            position = 0
            pending.each do |(idx, key, offsets)|
              last = flags[position, offsets.size].rindex(true)
              if last
                split_at = offsets[last]
                results[idx] = [
                  identifiers[position + last].force_encoding(key.encoding),
                  key.byteslice((prefix_bytes + split_at + delim.bytesize)..).force_encoding(key.encoding),
                ]
              end
              position += offsets.size
            end
            pending.clear
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
          # The fields are read from related_fields_snapshot, so a field
          # declared in another thread meanwhile does not make MRI raise
          # "can't add a new key into hash during iteration".
          #
          # @param owner [Familia::Horreum, Class] a record, or its class
          # @return [Hash{Symbol => Array<String>}] :fields and :indexes, as
          #   binary strings
          def record_set_key_names(owner)
            owner_class = owner_class_of(owner)
            fields = owner_class.related_fields_snapshot.each_value.filter_map do |definition|
              next if definition.opts[:dbkey]
              next unless definition.klass.is_a?(Class) && definition.klass <= Familia::UnsortedSet

              definition.name.to_s.b
            end
            indexes = Familia.multi_indexes(class_level: false).filter_map do |descriptor|
              descriptor.index_name.to_s.b if descriptor.scope_class == owner_class
            end
            { fields: fields, indexes: indexes }
          end
        end
      end
    end
  end
end
