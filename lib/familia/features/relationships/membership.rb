# lib/familia/features/relationships/membership.rb

module Familia
  module Features
    module Relationships
      # Membership module for member_of relationships
      # Provides collision-free method naming by including collection names
      module Membership
        # Class-level membership configurations
        def self.included(base)
          base.extend ModelClassMethods
          base.include ModelInstanceMethods
          super
        end

        module ModelClassMethods
          # Define a member_of relationship
          #
          # @param owner_class [Class] The class that owns the collection
          # @param collection_name [Symbol] Name of the collection on the owner
          # @param score [Symbol, Proc, nil] How to calculate the score for sorted sets
          # @param type [Symbol] Type of Valkey/Redis collection (:sorted_set, :set, :list)
          #
          # @example Basic membership
          #   member_of Customer, :domains
          #
          # @example Membership with scoring
          #   member_of Team, :projects, score: -> { permission_encode(Familia.now, permission_level) }
          def member_of(owner_class, collection_name, score: nil, type: :sorted_set)
            owner_class_name = owner_class.is_a?(Class) ? owner_class.name : owner_class.to_s.camelize

            # Store metadata for this membership relationship
            membership_relationships << {
              owner_class: owner_class,
              owner_class_name: owner_class_name,
              collection_name: collection_name,
              score: score,
              type: type,
            }

            # Generate instance methods with collision-free naming
            owner_class_name_lower = owner_class_name.downcase

            # Method to add this object to the owner's collection
            # e.g., domain.add_to_customer_domains(customer)
            define_method("add_to_#{owner_class_name_lower}_#{collection_name}") do |owner_instance, score = nil|
              collection = owner_instance.send(collection_name)
              collection.add(identifier, score: score)
            end

            # Method to remove this object from the owner's collection
            # e.g., domain.remove_from_customer_domains(customer)
            define_method("remove_from_#{owner_class_name_lower}_#{collection_name}") do |owner_instance|
              collection = owner_instance.send(collection_name)
              collection.remove(identifier)
            end

            # Method to check if this object is in the owner's collection
            # e.g., domain.in_customer_domains?(customer)
            define_method("in_#{owner_class_name_lower}_#{collection_name}?") do |owner_instance|
              collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"

              # TODO: We should be able to reduce this to a single method call on the DataType class
              # instance, like we do for remove above (why: each the HashKey, SortedSet, UnsortedSet,
              # and List classes have a `remove` method that implements the correct behaviour).
              case type
              when :sorted_set
                !dbclient.zscore(collection_key, identifier).nil?
              when :set
                dbclient.sismember(collection_key, identifier)
              when :list
                dbclient.lpos(collection_key, identifier) != nil
              end
            end

            # Method to get score in the owner's collection (for sorted sets)
            # e.g., domain.score_in_customer_domains(customer)
            if type == :sorted_set
              define_method("score_in_#{owner_class_name_lower}_#{collection_name}") do |owner_instance|
                collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"
                dbclient.zscore(collection_key, identifier)
              end
            end

            # Method to get position in the owner's collection (for lists)
            # e.g., domain.position_in_customer_domain_list(customer)
            return unless type == :list

            define_method("position_in_#{owner_class_name_lower}_#{collection_name}") do |owner_instance|
              collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"
              position = dbclient.lpos(collection_key, identifier)
              position
            end
          end

          # Get all membership relationships for this class
          def membership_relationships
            @membership_relationships ||= []
          end

          private

          # Generate collision-free instance methods for membership
          def generate_membership_instance_methods(owner_class_name, collection_name, _score_calculator, type)
            owner_class_name_lower = owner_class_name.downcase

            # Method to add this object to the owner's collection
            # e.g., domain.add_to_customer_domains(customer)
            define_method("add_to_#{owner_class_name_lower}_#{collection_name}") do |owner_instance, score = nil|
              collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"

              # TODO: We should be able to reduce this to a single method call on the DataType class
              # instance, like we do for remove above (why: each the HashKey, SortedSet, UnsortedSet,
              # and List classes have a `remove` method that implements the correct behaviour).
              case type
              when :sorted_set
                # Find the owner class from the stored config
                membership_config = self.class.membership_relationships.find do |config|
                  config[:owner_class_name] == owner_class_name && config[:collection_name] == collection_name
                end
                owner_class = membership_config[:owner_class] if membership_config
                score ||= calculate_membership_score(owner_class, collection_name)
                dbclient.zadd(collection_key, score, identifier)
              when :set
                dbclient.sadd(collection_key, identifier)
              when :list
                dbclient.lpush(collection_key, identifier)
              end
            end

            # Method to remove this object from the owner's collection
            # e.g., domain.remove_from_customer_domains(customer)
            define_method("remove_from_#{owner_class_name_lower}_#{collection_name}") do |owner_instance|
              collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"

              # TODO: We should be able to reduce this to a single method call on the DataType class
              # instance, like we do for remove above (why: each the HashKey, SortedSet, UnsortedSet,
              # and List classes have a `remove` method that implements the correct behaviour).
              case type
              when :sorted_set
                dbclient.zrem(collection_key, identifier)
              when :set
                dbclient.srem(collection_key, identifier)
              when :list
                dbclient.lrem(collection_key, 0, identifier) # Remove all occurrences
              end
            end

            # Method to check if this object is in the owner's collection
            # e.g., domain.in_customer_domains?(customer)
            define_method("in_#{owner_class_name_lower}_#{collection_name}?") do |owner_instance|
              collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"

              # TODO: We should be able to reduce this to a single method call on the DataType class
              # instance, like we do for remove above (why: each the HashKey, SortedSet, UnsortedSet,
              # and List classes have a `remove` method that implements the correct behaviour).
              case type
              when :sorted_set
                dbclient.zscore(collection_key, identifier) != nil
              when :set
                dbclient.sismember(collection_key, identifier)
              when :list
                dbclient.lpos(collection_key, identifier) != nil
              end
            end

            # For sorted sets, add methods to get and update scores
            if type == :sorted_set
              # Method to get score in the owner's collection
              # e.g., domain.score_in_customer_domains(customer)
              define_method("score_in_#{owner_class_name_lower}_#{collection_name}") do |owner_instance|
                collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"
                dbclient.zscore(collection_key, identifier)
              end

              # Method to update score in the owner's collection
              # e.g., domain.update_score_in_customer_domains(customer, new_score)
              define_method("update_score_in_#{owner_class_name_lower}_#{collection_name}") do |owner_instance, new_score|
                collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"
                dbclient.zadd(collection_key, new_score, identifier, xx: true) # Only update existing
              end

              # Method to get rank in the owner's collection
              # e.g., domain.rank_in_customer_domains(customer)
              define_method("rank_in_#{owner_class_name_lower}_#{collection_name}") do |owner_instance, reverse: false|
                collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"
                if reverse
                  dbclient.zrevrank(collection_key, identifier)
                else
                  dbclient.zrank(collection_key, identifier)
                end
              end
            end

            # For lists, add position-related methods
            if type == :list
              # Method to get position in the owner's list
              # e.g., domain.position_in_customer_domains(customer)
              define_method("position_in_#{owner_class_name_lower}_#{collection_name}") do |owner_instance|
                collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"
                dbclient.lpos(collection_key, identifier)
              end

              # Method to move to specific position in the owner's list
              # e.g., domain.move_in_customer_domains(customer, new_position)
              define_method("move_in_#{owner_class_name_lower}_#{collection_name}") do |owner_instance, new_position|
                collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"

                # Remove and re-insert at new position
                dbclient.multi do |tx|
                  tx.lrem(collection_key, 1, identifier)

                  if new_position.zero?
                    tx.lpush(collection_key, identifier)
                  elsif new_position == -1
                    tx.rpush(collection_key, identifier)
                  else
                    # For arbitrary positions, we need to use a more complex approach
                    # This is simplified - proper implementation would handle edge cases
                    tx.linsert(collection_key, 'BEFORE', dbclient.lindex(collection_key, new_position), identifier)
                  end
                end
              end
            end

            # Method to get all owners that contain this object in the specified collection
            # e.g., domain.all_customer_domains_owners
            define_method("all_#{owner_class_name_lower}_#{collection_name}_owners") do
              owners = []
              pattern = "#{owner_class_name_lower}:*:#{collection_name}"

              dbclient.scan_each(match: pattern) do |key|
                owner_id = key.split(':')[1]

                # Check if this object is in this collection
                is_member = case type
                            when :sorted_set
                              dbclient.zscore(key, identifier) != nil
                            when :set
                              dbclient.sismember(key, identifier)
                            when :list
                              dbclient.lpos(key, identifier) != nil
                            end

                if is_member
                  # Try to instantiate the owner object
                  begin
                    owners << owner_class.new(identifier: owner_id)
                  rescue NameError
                    # Owner class not available, just store the ID
                    owners << { class: owner_class_name, id: owner_id }
                  end
                end
              end

              owners
            end

            # Batch method to add to multiple owners' collections at once
            # e.g., domain.add_to_multiple_customer_domains([customer1, customer2])
            define_method("add_to_multiple_#{owner_class_name_lower}_#{collection_name}") do |owner_instances, score = nil|
              return if owner_instances.empty?

              dbclient.pipelined do |pipeline|
                owner_instances.each do |owner_instance|
                  collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"

                  case type
                  when :sorted_set
                    # Find the owner class from the stored config
                    membership_config = self.class.membership_relationships.find do |config|
                      config[:owner_class_name] == owner_class_name && config[:collection_name] == collection_name
                    end
                    owner_class = membership_config[:owner_class] if membership_config
                    calculated_score = score || calculate_membership_score(owner_class, collection_name)
                    pipeline.zadd(collection_key, calculated_score, identifier)
                  when :set
                    pipeline.sadd(collection_key, identifier)
                  when :list
                    pipeline.lpush(collection_key, identifier)
                  end
                end
              end
            end

            # Batch method to remove from multiple owners' collections at once
            # e.g., domain.remove_from_multiple_customer_domains([customer1, customer2])
            define_method("remove_from_multiple_#{owner_class_name_lower}_#{collection_name}") do |owner_instances|
              return if owner_instances.empty?

              dbclient.pipelined do |pipeline|
                owner_instances.each do |owner_instance|
                  collection_key = "#{owner_class_name_lower}:#{owner_instance.identifier}:#{collection_name}"

                  case type
                  when :sorted_set
                    pipeline.zrem(collection_key, identifier)
                  when :set
                    pipeline.srem(collection_key, identifier)
                  when :list
                    pipeline.lrem(collection_key, 0, identifier)
                  end
                end
              end
            end
          end
        end

        # Instance methods for objects with membership relationships
        module ModelInstanceMethods
          # Calculate the appropriate score for a membership relationship
          #
          # @param owner_class [Class] The owner class (e.g., Customer)
          # @param collection_name [Symbol] The collection name (e.g., :domains)
          # @return [Float] Calculated score
          def calculate_membership_score(owner_class, collection_name)
            # Find the membership configuration
            membership_config = self.class.membership_relationships.find do |config|
              config[:owner_class] == owner_class && config[:collection_name] == collection_name
            end

            return default_score unless membership_config

            score_calculator = membership_config[:score]

            # Extract the score calculation logic to reduce complexity
            calculated_score = extract_score_from_calculator(score_calculator)
            calculated_score || default_score
          end

          private

          def extract_score_from_calculator(score_calculator)
            case score_calculator
            when Symbol
              extract_score_from_symbol(score_calculator)
            when Proc
              extract_score_from_proc(score_calculator)
            when Numeric
              score_calculator.to_f
            end
          end

          def extract_score_from_symbol(symbol)
            return nil unless respond_to?(symbol)

            value = send(symbol)
            if value.respond_to?(:to_f)
              value.to_f
            elsif value.respond_to?(:to_i)
              encode_score(value, 0)
            end
          end

          def extract_score_from_proc(proc)
            result = instance_exec(&proc)
            return nil if result.nil?

            result.respond_to?(:to_f) ? result.to_f : nil
          end

          def default_score
            respond_to?(:current_score) ? current_score : Familia.now
          end

          # Update membership in all collections atomically
          def update_all_memberships(_action = :add)
            nil unless self.class.respond_to?(:membership_relationships)

            # This is a simplified version - in practice, you'd need to know
            # which specific owner instances this object should be a member of
            # For now, we'll skip the automatic update and rely on explicit calls
          end

          # Remove from all membership collections (used during destroy)
          def remove_from_all_memberships
            return unless self.class.respond_to?(:membership_relationships)

            self.class.membership_relationships.each do |config|
              owner_class_name = config[:owner_class_name]
              collection_name = config[:collection_name]
              type = config[:type]

              # Find all collections this object is a member of
              pattern = "#{owner_class_name.downcase}:*:#{collection_name}"

              dbclient.scan_each(match: pattern) do |key|
                case type
                when :sorted_set
                  dbclient.zrem(key, identifier)
                when :set
                  dbclient.srem(key, identifier)
                when :list
                  dbclient.lrem(key, 0, identifier)
                end
              end
            end
          end

          # Get all memberships this object has
          #
          # @return [Array<Hash>] Array of membership information
          def membership_collections
            return [] unless self.class.respond_to?(:membership_relationships)

            memberships = []

            self.class.membership_relationships.each do |config|
              owner_class_name = config[:owner_class_name]
              collection_name = config[:collection_name]
              type = config[:type]

              # Find all collections this object is a member of
              pattern = "#{owner_class_name.downcase}:*:#{collection_name}"

              dbclient.scan_each(match: pattern) do |key|
                is_member = case type
                            when :sorted_set
                              score = dbclient.zscore(key, identifier)
                              next unless score

                              { score: score, decoded_score: decode_score(score) }
                            when :set
                              next unless dbclient.sismember(key, identifier)

                              {}
                            when :list
                              position = dbclient.lpos(key, identifier)
                              next unless position

                              { position: position }
                            end

                if is_member
                  owner_id = key.split(':')[1]
                  memberships << {
                    owner_class: owner_class_name,
                    owner_id: owner_id,
                    collection_name: collection_name,
                    type: type,
                    key: key,
                  }.merge(is_member)
                end
              end
            end

            memberships
          end

          # Transfer membership from one owner to another
          #
          # @param from_owner [Object] Source owner instance
          # @param to_owner [Object] Target owner instance
          # @param collection_name [Symbol] Collection to transfer membership in
          def transfer_membership(from_owner, to_owner, collection_name)
            # Find the membership configuration
            config = self.class.membership_relationships.find do |rel|
              rel[:collection_name] == collection_name &&
                (rel[:owner_class] == from_owner.class || rel[:owner_class_name] == from_owner.class.name)
            end

            return false unless config

            owner_class_name = config[:owner_class_name].downcase
            type = config[:type]

            from_key = "#{owner_class_name}:#{from_owner.identifier}:#{collection_name}"
            to_key = "#{owner_class_name}:#{to_owner.identifier}:#{collection_name}"

            dbclient.multi do |tx|
              case type
              when :sorted_set
                score = dbclient.zscore(from_key, identifier)
                if score
                  tx.zrem(from_key, identifier)
                  tx.zadd(to_key, score, identifier)
                end
              when :set
                if dbclient.sismember(from_key, identifier)
                  tx.srem(from_key, identifier)
                  tx.sadd(to_key, identifier)
                end
              when :list
                if dbclient.lpos(from_key, identifier)
                  tx.lrem(from_key, 1, identifier)
                  tx.lpush(to_key, identifier)
                end
              end
            end

            true
          end
        end
      end
    end
  end
end
