# lib/familia/features/relationships/participation.rb

require_relative 'participation_relationship'
require_relative 'collection_operations'
require_relative 'participation/participant_methods'
require_relative 'participation/target_methods'

module Familia
  module Features
    module Relationships
      # Participation module for bidirectional business relationships using Valkey/Redis collections.
      # Provides semantic, scored relationships with automatic reverse tracking.
      #
      # Unlike Indexing (which is for attribute lookups), Participation manages
      # relationships where membership has meaning, scores have semantic value,
      # and bidirectional tracking is essential
      #
      # === Architecture Overview ===
      # This module is organized into clear, separate concerns:
      #
      # 1. CollectionOperations: Shared helpers for all collection manipulation
      # 2. ParticipantMethods: Methods added to the class calling participates_in
      # 3. TargetMethods: Methods added to the target class specified in participates_in
      #
      # This separation makes it crystal clear what methods are added to which class.
      #
      # @example Basic participation with temporal scoring
      #   class Domain < Familia::Horreum
      #     feature :relationships
      #     field :created_at
      #     participates_in Customer, :domains, score: :created_at
      #   end
      #
      #   # TARGET (Customer) gets collection management:
      #   customer.domains                    # → Familia::SortedSet (by created_at)
      #   customer.add_domain(domain)         # → adds with created_at score
      #   customer.remove_domain(domain)      # → removes + cleans reverse index
      #   customer.add_domains([d1, d2, d3])  # → efficient bulk addition
      #
      #   # PARTICIPANT (Domain) gets membership methods:
      #   domain.in_customer_domains?(customer)              # → true/false
      #   domain.add_to_customer_domains(customer)           # → self-addition
      #   domain.remove_from_customer_domains(customer)      # → self-removal
      #   domain.participations                              # → reverse index tracking
      #
      # @example Class-level participation (all instances auto-tracked)
      #   class User < Familia::Horreum
      #     feature :relationships
      #     field :created_at
      #     class_participates_in :all_users, score: :created_at
      #   end
      #
      #   User.all_users              # → Familia::SortedSet (class-level)
      #   user.in_class_all_users?    # → true if auto-added
      #   user.add_to_class_all_users # → explicit addition
      #
      # @example Semantic scores with permission encoding
      #   class Domain < Familia::Horreum
      #     feature :relationships
      #     field :created_at
      #     field :permission_bits
      #
      #     participates_in Customer, :domains,
      #       score: -> { permission_encode(created_at, permission_bits) }
      #   end
      #
      #   customer.domains_with_permission(:read)  # → filtered by score
      #
      # Key Differences from Indexing:
      # - Participation: Bidirectional relationships with semantic scores
      # - Indexing: Unidirectional lookups without relationship semantics
      # - Participation: Collection name in key (customer:123:domains)
      # - Indexing: Field value in key (company:123:dept_index:engineering)
      #
      # When to Use Participation:
      # - Modeling business relationships (Customer owns Domains)
      # - Scores have meaning (priority, permissions, join_date)
      # - Need bidirectional tracking ("what collections does this belong to?")
      # - Relationship lifecycle matters (cascade cleanup, reverse tracking)
      #
      module Participation
        using Familia::Refinements::StylizeWords

        # Hook called when module is included in a class.
        #
        # Extends the host class with ModelClassMethods for relationship definitions
        # and includes ModelInstanceMethods for instance-level operations.
        #
        # @param base [Class] The class including this module
        def self.included(base)
          base.extend ModelClassMethods
          base.include ModelInstanceMethods
          super
        end

        # Class methods for defining participation relationships.
        #
        # These methods are available on any class that includes the Participation module,
        # allowing definition of both instance-level and class-level participation relationships.
        module ModelClassMethods
          # Define a class-level participation collection where all instances automatically participate.
          #
          # Class-level participation creates a global collection containing all instances of the class,
          # with automatic management of membership based on object lifecycle events. This is useful
          # for maintaining global indexes, leaderboards, or categorical groupings.
          #
          # The collection is created at the class level (e.g., User.all_users) rather than on
          # individual instances, providing a centralized view of all objects matching the criteria.
          #
          # === Generated Methods
          #
          # ==== On the Class (Target Methods)
          # - +ClassName.collection_name+ - Access the collection DataType
          # - +ClassName.add_to_collection_name(instance)+ - Add instance to collection
          # - +ClassName.remove_from_collection_name(instance)+ - Remove instance from collection
          #
          # ==== On Instances (Participant Methods, if bidirectional)
          # - +instance.in_class_collection_name?+ - Check membership in class collection
          # - +instance.add_to_class_collection_name+ - Add self to class collection
          # - +instance.remove_from_class_collection_name+ - Remove self from class collection
          #
          # @param collection_name [Symbol] Name of the class-level collection (e.g., +:all_users+, +:active_members+)
          # @param score [Symbol, Proc, Numeric, nil] Scoring strategy for sorted collections:
          #   - +Symbol+: Field name or method name (e.g., +:priority_level+, +:created_at+)
          #   - +Proc+: Dynamic calculation in instance context (e.g., +-> { status == 'premium' ? 100 : 0 }+)
          #   - +Numeric+: Static score for all instances (e.g., +50.0+)
          #   - +nil+: Use +current_score+ method fallback
          #   - +:remove+: Remove from collection on destruction (default)
          #   - +:ignore+: Leave in collection when destroyed
          # @param type [Symbol] Valkey/Redis collection type:
          #   - +:sorted_set+: Ordered by score (default)
          #   - +:set+: Unordered unique membership
          #   - +:list+: Ordered sequence allowing duplicates
          # @param bidirectional [Boolean] Whether to generate convenience methods on instances (default: +true+)
          #
          # @example Simple priority-based global collection
          #   class User < Familia::Horreum
          #     field :priority_level
          #     class_participates_in :all_users, score: :priority_level
          #   end
          #
          #   User.all_users.first        # Highest priority user
          #   user.in_class_all_users?    # true if user is in collection
          #
          # @example Dynamic scoring based on status
          #   class Customer < Familia::Horreum
          #     field :status
          #     field :last_purchase
          #
          #     class_participates_in :active_customers, score: -> {
          #       status == 'active' ? last_purchase.to_i : 0
          #     }
          #   end
          #
          #   Customer.active_customers.to_a  # All active customers, sorted by last purchase
          #
          # @see #participates_in for instance-level participation relationships
          # @since 1.0.0
          def class_participates_in(collection_name, score: nil,
                                    type: :sorted_set, bidirectional: true)
            # Store metadata for this participation relationship
            participation_relationships << ParticipationRelationship.new(
              target_class: self,
              collection_name: collection_name,
              score: score,

              type: type,
              bidirectional: bidirectional,
            )

            # STEP 1: Add collection management methods to the class itself
            # e.g., User.all_users, User.add_to_all_users(user)
            TargetMethods::Builder.build_class_level(self, collection_name, type)

            # STEP 2: Add participation methods to instances (if bidirectional)
            # e.g., user.in_class_all_users?, user.add_to_class_all_users
            return unless bidirectional

            # Pass the string 'class' as target to distinguish class-level from instance-level
            # This prevents generating reverse collection methods (user can't have "all_users")
            # See ParticipantMethods::Builder.build for handling of this special case
            ParticipantMethods::Builder.build(self, 'class', collection_name, type, nil)
          end

          # Define an instance-level participation relationship between two classes.
          #
          # This method creates a bidirectional relationship where instances of the calling class
          # (participants) can join collections owned by instances of the target class. This enables
          # flexible multi-membership scenarios where objects can belong to multiple collections
          # simultaneously with different scoring and management strategies.
          #
          # The relationship automatically handles reverse index tracking, allowing efficient
          # lookup of all collections a participant belongs to via the +current_participations+ method.
          #
          # === Generated Methods
          #
          # ==== On Target Class (Collection Owner)
          # - +target.collection_name+ - Access the collection DataType
          # - +target.add_participant_class_name(participant)+ - Add participant to collection
          # - +target.remove_participant_class_name(participant)+ - Remove participant from collection
          # - +target.add_participant_class_names([participants])+ - Bulk add multiple participants
          #
          # ==== On Participant Class (if bidirectional)
          # - +participant.in_target_collection_name?(target)+ - Check membership in target's collection
          # - +participant.add_to_target_collection_name(target)+ - Add self to target's collection
          # - +participant.remove_from_target_collection_name(target)+ - Remove self from target's collection
          #
          # === Reverse Index Tracking
          #
          # Automatically creates a +:participations+ set field on the participant class to track
          # all collections the instance belongs to. This enables efficient membership queries
          # and cleanup operations without scanning all possible collections.
          #
          # @param target [Class, Symbol, String] The class that owns the collection. Can be:
          #   - +Class+ object (e.g., +Employee+)
          #   - +Symbol+ referencing class name (e.g., +:employee+, +:Employee+)
          #   - +String+ class name (e.g., +"Employee"+)
          # @param collection_name [Symbol] Name of the collection on the
          #        target class (e.g., +:domains+, +:members+)
          # @param score [Symbol, Proc, Numeric, nil] Scoring strategy for
          #        sorted collections:
          #   - +Symbol+: Field name or method name (e.g., +:priority+, +:created_at+)
          #   - +Proc+: Dynamic calculation executed in participant instance context
          #   - +Numeric+: Static score applied to all participants
          #   - +nil+: Use +current_score+ method as fallback
          #   - +:remove+: Remove from all collections on destruction (default)
          #   - +:ignore+: Leave in collections when destroyed
          # @param type [Symbol] Valkey/Redis collection type:
          #   - +:sorted_set+: Ordered by score, allows duplicates with
          #        different scores (default)
          #   - +:set+: Unordered unique membership
          #   - +:list+: Ordered sequence, allows duplicates
          # @param bidirectional [Boolean, Symbol] Whether to generate convenience
          #        methods on participant class. When a Symbol is passed, it is
          #        used as the name of the method to be generated. Otherwise the
          #        name of the target class is used. (default: +true+)
          #
          # @example Basic domain-employee relationship
          #
          #   class Domain < Familia::Horreum
          #     field :name
          #     field :created_at
          #
          #     participates_in Employee, :domains, score: :created_at
          #   end
          #
          #   # Usage:
          #   domain.add_to_customer_domains(customer)  # Add domain to customer's collection
          #   customer.domains.first                    # Most recent domain
          #   domain.in_customer_domains?(customer)     # true
          #   domain.current_participations             # All collections domain belongs to
          #
          # @example Multi-collection participation with different types
          #
          #   class Employee < Familia::Horreum
          #     field :hire_date
          #     field :skill_level
          #
          #     # Sorted by hire date in department
          #     participates_in Department, :members, score: :hire_date
          #
          #     # Simple set membership in teams
          #     participates_in Team, :contributors, score: :skill_level, type: :set
          #
          #     # Complex scoring for project assignments
          #     participates_in Project, :assignees, score: -> {
          #       base_score = skill_level * 100
          #       seniority = (Time.now - hire_date) / 1.year
          #       base_score + seniority * 10
          #     }
          #   end
          #
          #   # Employee can belong to department, multiple teams, and projects
          #   employee.add_to_department_members(engineering_dept)
          #   employee.add_to_team_contributors(frontend_team)
          #   employee.add_to_project_assignees(mobile_app_project)
          #
          # @see #class_participates_in for class-level participation
          # @see ModelInstanceMethods#current_participations for membership queries
          # @see ModelInstanceMethods#calculate_participation_score for scoring details
          #
          def participates_in(target, collection_name, score: nil, type: :sorted_set, bidirectional: true, as: nil)

            # Normalize the
            target_class = Familia.resolve_class(target)

            # Raise helpful error if target class can't be resolved
            if target_class.nil?
              raise ArgumentError, <<~ERROR
                Cannot resolve target class: #{target.inspect}

                The target class '#{target}' could not be found in Familia.members.
                This usually means:
                1. The target class hasn't been loaded/required yet (load order issue)
                2. The target class name is misspelled
                3. The target class doesn't inherit from Familia::Horreum

                Current registered classes: #{Familia.members.filter_map(&:name).sort.join(', ')}

                Solution: Ensure #{target_class} is defined and loaded before #{name}
              ERROR
            end

            # Store metadata for this participation relationship
            participation_relationships << ParticipationRelationship.new(
              target_class: target, # as passed to `participates_in`
              collection_name: collection_name,
              score: score,
              type: type,
              bidirectional: bidirectional,
            )

            # STEP 0: Add participations tracking field to PARTICIPANT class (Domain)
            # This creates the proper key: "domain:123:participations"
            set :participations unless method_defined?(:participations)

            # STEP 1: Add collection management methods to TARGET class (Employee)
            # Employee gets: domains, add_domain, remove_domain, etc.
            TargetMethods::Builder.build(target_class, collection_name, type)

            # STEP 2: Add participation methods to PARTICIPANT class (Domain) - only if
            # bidirectional. e.g. in_employee_domains?, add_to_employee_domains, etc.
            if bidirectional
              # `as` parameter allows custom naming for reverse collections
              # If not provided, we'll let the builder use the pluralized target class name
              ParticipantMethods::Builder.build(self, target_class, collection_name, type, as)
            end
          end

          # Get all participation relationships defined for this class.
          #
          # Returns an array of ParticipationRelationship objects containing metadata
          # about each participation relationship, including target class, collection name,
          # scoring strategy, and configuration options.
          #
          # @return [Array<ParticipationRelationship>] Array of relationship configurations
          # @since 1.0.0
          def participation_relationships
            @participation_relationships ||= []
          end
        end

        # Instance methods available on objects that participate in collections.
        #
        # These methods provide the core functionality for participation management,
        # including score calculation, membership tracking, and participation queries.
        module ModelInstanceMethods
          # Calculate the appropriate score for a participation relationship based on configured scoring strategy.
          #
          # This method serves as the single source of truth for participation scoring across the entire
          # relationship lifecycle. It supports multiple scoring strategies and provides robust fallback
          # behavior for edge cases and error conditions.
          #
          # The calculated score determines the object's position within sorted collections and can be
          # dynamically recalculated as object state changes, enabling responsive collection ordering
          # based on real-time business logic.
          #
          # === Scoring Strategies
          #
          # [Symbol] Field name or method name - calls +send(symbol)+ on the instance
          #   * +:priority_level+ - Uses value of priority_level field
          #   * +:created_at+ - Uses timestamp for chronological ordering
          #   * +:calculate_importance+ - Calls custom method for complex logic
          #
          # [Proc] Dynamic calculation executed in instance context using +instance_exec+
          #   * +-> { skill_level * experience_years }+ - Combines multiple fields
          #   * +-> { active? ? 100 : 0 }+ - Conditional scoring based on state
          #   * +-> { Rails.cache.fetch("score:#{id}") { expensive_calculation } }+ - Cached computations
          #
          # [Numeric] Static score applied uniformly to all instances
          #   * +50.0+ - All instances get same floating-point score
          #   * +100+ - All instances get same integer score (converted to float)
          #
          # [nil] Uses +current_score+ method as fallback if available
          #
          # === Performance Considerations
          #
          # - Score calculations are performed on-demand during collection operations
          # - Proc-based calculations should be efficient as they may be called frequently
          # - Consider caching expensive calculations within the Proc itself
          # - Static numeric scores have no performance overhead
          #
          # === Thread Safety
          #
          # Score calculations should be idempotent and thread-safe since they may be
          # called concurrently during collection updates. Avoid modifying instance state
          # within scoring Procs.
          #
          # @param target_class [Class, Symbol, String] The target class containing the collection
          #   - For instance-level participation: Class object (e.g., +Project+, +Team+)
          #   - For class-level participation: The string +'class'+ (from +class_participates_in+)
          # @param collection_name [Symbol] The collection name within the target class
          # @return [Float] Calculated score for sorted set positioning, falls back to current_score
          #
          # @example Field-based scoring
          #   class Task < Familia::Horreum
          #     field :priority  # 1=low, 5=high
          #     participates_in Project, :tasks, score: :priority
          #   end
          #
          #   task.priority = 5
          #   score = task.calculate_participation_score(Project, :tasks)  # => 5.0
          #
          # @example Complex business logic with multiple factors
          #   class Employee < Familia::Horreum
          #     field :hire_date
          #     field :performance_rating
          #     field :salary
          #
          #     participates_in Department, :members, score: -> {
          #       tenure_months = (Time.now - hire_date) / 1.month
          #       base_score = tenure_months * 10
          #       performance_bonus = performance_rating * 100
          #       salary_factor = salary / 1000.0
          #
          #       (base_score + performance_bonus + salary_factor).round(2)
          #     }
          #   end
          #
          #   # Score reflects seniority, performance, and compensation
          #   employee.performance_rating = 4.5
          #   employee.salary = 85000
          #   score = employee.calculate_participation_score(Department, :members)  # => 1375.0
          #
          # @see #participates_in for relationship configuration
          # @see #track_participation_in for reverse index management
          # @since 1.0.0
          def calculate_participation_score(target_class, collection_name)
            # Find the participation configuration with robust type comparison
            participation_config = self.class.participation_relationships.find do |details|
              # Normalize both sides for comparison to handle Class, Symbol, and String types
              config_target = details.target_class
              config_target = config_target.name if config_target.is_a?(Class)
              config_target = config_target.to_s

              comparison_target = target_class
              comparison_target = comparison_target.name if comparison_target.is_a?(Class)
              comparison_target = comparison_target.to_s

              config_target == comparison_target && details.collection_name == collection_name
            end

            return current_score unless participation_config

            score_calculator = participation_config.score

            # Get the raw result based on calculator type
            result = case score_calculator
                     when Symbol
                       # Field name or method name
                       respond_to?(score_calculator) ? send(score_calculator) : nil
                     when Proc
                       # Execute proc in context of this instance
                       instance_exec(&score_calculator)
                     when Numeric
                       # Static numeric value
                       return score_calculator.to_f
                     else
                       # Unrecognized type
                       return current_score
            end

            # Convert result to appropriate score with unified logic
            convert_to_score(result)
          end

          # Add participation tracking to the reverse index.
          #
          # This method maintains the reverse index that tracks which collections this object
          # participates in. The reverse index enables efficient lookup of all memberships
          # via +current_participations+ without requiring expensive scans.
          #
          # The collection key follows the pattern: +"targetclass:targetid:collectionname"+
          #
          # @param collection_key [String] Unique identifier for the collection (format: "class:id:collection")
          # @example
          #   domain.track_participation_in("customer:123:domains")
          # @see #untrack_participation_in for removal
          # @see #current_participations for membership queries
          # @since 1.0.0
          def track_participation_in(collection_key)
            # Use Horreum's DataType field instead of manual key construction
            participations.add(collection_key)
          end

          # Remove participation tracking from the reverse index.
          #
          # This method removes the collection key from the reverse index when the object
          # is removed from a collection. This keeps the reverse index accurate and prevents
          # stale references from appearing in +current_participations+ results.
          #
          # @param collection_key [String] Collection identifier to remove from tracking
          # @example
          #   domain.untrack_participation_in("customer:123:domains")
          # @see #track_participation_in for addition
          # @see #current_participations for membership queries
          # @since 1.0.0
          def untrack_participation_in(collection_key)
            # Use Horreum's DataType field instead of manual key construction
            participations.remove(collection_key)
          end

          # Get comprehensive information about all collections this object participates in.
          #
          # This method leverages the reverse index to efficiently retrieve membership details
          # across all collections without requiring expensive scans. For each membership,
          # it provides collection metadata, membership details, and type-specific information
          # like scores or positions.
          #
          # The method handles missing target objects gracefully and validates membership
          # using the actual DataType collections to ensure accuracy.
          #
          # === Return Format
          #
          # Returns an array of hashes, each containing:
          # - +:target_class+ - Name of the class owning the collection
          # - +:target_id+ - Identifier of the specific target instance
          # - +:collection_name+ - Name of the collection within the target
          # - +:type+ - Collection type (:sorted_set, :set, :list)
          #
          # Additional fields based on collection type:
          # - +:score+ - Current score (sorted_set only)
          # - +:decoded_score+ - Human-readable score if decode_score method exists
          # - +:position+ - Zero-based position in the list (list only)
          #
          # @return [Array<Hash>] Array of membership details with collection metadata
          #
          # @example Employee participating in multiple collections
          #   class Employee < Familia::Horreum
          #     field :name
          #     participates_in Department, :members, score: :hire_date
          #     participates_in Team, :contributors, score: :skill_level, type: :set
          #     participates_in Project, :assignees, score: :priority, type: :list
          #   end
          #
          #   employee.add_to_department_members(engineering)
          #   employee.add_to_team_contributors(frontend_team)
          #   employee.add_to_project_assignees(mobile_project)
          #
          #   # Query all memberships
          #   memberships = employee.current_participations
          #   # => [
          #   #   {
          #   #     target_class: "Department",
          #   #     target_id: "engineering",
          #   #     collection_name: :members,
          #   #     type: :sorted_set,
          #   #     score: 1640995200.0,
          #   #     decoded_score: "2022-01-01 00:00:00 UTC"
          #   #   },
          #   #   {
          #   #     target_class: "Team",
          #   #     target_id: "frontend",
          #   #     collection_name: :contributors,
          #   #     type: :set
          #   #   },
          #   #   {
          #   #     target_class: "Project",
          #   #     target_id: "mobile",
          #   #     collection_name: :assignees,
          #   #     type: :list,
          #   #     position: 2
          #   #   }
          #   # ]
          #
          # @see #track_participation_in for reverse index management
          # @see #calculate_participation_score for scoring details
          # @since 1.0.0
          # Get all IDs where this instance participates for a specific target class
          #
          # Optimized to iterate through keys once and use Set for efficient uniqueness,
          # reducing string operations and object allocations.
          #
          # @param target_class [Class] The target class to filter by
          # @param collection_names [Array<String>, nil] Optional collection name filter
          # @return [Array<String>] Array of unique target instance IDs
          def participating_ids_for_target(target_class, collection_names = nil)
            require 'set'

            # Use config_name to get the proper snake_case format (e.g., "project_team")
            target_prefix = "#{target_class.config_name}:"
            ids = Set.new

            participations.members.each do |key|
              next unless key.start_with?(target_prefix)

              parts = key.split(':', 3)  # Split into ["targetclass", "id", "collection"]
              id = parts[1]

              # If filtering by collection names, check before adding
              if collection_names && !collection_names.empty?
                collection = parts[2]
                ids << id if collection_names.include?(collection)
              else
                ids << id
              end
            end

            ids.to_a
          end

          def current_participations
            return [] unless self.class.respond_to?(:participation_relationships)

            # Use the reverse index as the single source of truth
            collection_keys = participations.members
            return [] if collection_keys.empty?

            memberships = []

            # Check membership in each tracked collection using DataType methods
            collection_keys.each do |collection_key|
              # Parse the collection key to extract target info
              # Expected format: "targetclass:targetid:collectionname"
              key_parts = collection_key.split(':')
              next unless key_parts.length >= 3

              target_class_config = key_parts[0]
              target_id = key_parts[1]
              collection_name_from_key = key_parts[2]

              # Find the matching participation configuration
              # Note: target_class_config from key is snake_case
              config = self.class.participation_relationships.find do |cfg|
                cfg.target_class_config_name == target_class_config &&
                  cfg.collection_name.to_s == collection_name_from_key
              end

              next unless config

              # Find the target instance and check membership using Horreum DataTypes
              begin
                target_class = Familia.resolve_class(config.target_class)
                target_instance = target_class.find_by_id(target_id)
                next unless target_instance

                # Use Horreum's DataType accessor to get the collection
                collection = target_instance.send(config.collection_name)

                # Check membership using DataType methods
                membership_data = {
                  target_class: target_class.familia_name,
                  target_id: target_id,
                  collection_name: config.collection_name,
                  type: config.type,
                }

                case config.type
                when :sorted_set
                  score = collection.score(identifier)
                  next unless score

                  membership_data[:score] = score
                  membership_data[:decoded_score] = decode_score(score) if respond_to?(:decode_score)
                when :set
                  is_member = collection.member?(identifier)
                  next unless is_member
                when :list
                  position = collection.to_a.index(identifier)
                  next unless position

                  membership_data[:position] = position
                end

                memberships << membership_data
              rescue StandardError => e
                Familia.debug "[#{collection_key}] Error checking membership: #{e.message}"
                next
              end
            end

            memberships
          end

          private

          # Convert a raw value to an appropriate participation score.
          #
          # This private method handles the final conversion step for participation scores,
          # providing robust type coercion and fallback behavior for edge cases. It's called
          # by +calculate_participation_score+ after the scoring strategy has produced a raw value.
          #
          # The method never raises exceptions, always returning a valid Float value
          # suitable for use in Valkey/Redis sorted sets. Invalid or missing values
          # gracefully fall back to the +current_score+ method.
          #
          # === Conversion Strategy
          #
          # [Numeric types] Convert using +to_f+ for floating-point precision
          # [Integer-like] Use +encode_score+ if available, otherwise convert to float
          # [nil values] Fall back to +current_score+ method
          # [Other types] Fall back to +current_score+ method
          #
          # @param value [Object] The raw value to convert to a participation score
          # @return [Float] Converted score suitable for sorted set operations
          # @api private
          # @since 1.0.0
          def convert_to_score(value)
            return current_score if value.nil?

            if value.respond_to?(:to_f)
              value.to_f
            elsif value.respond_to?(:to_i)
              encode_score(value, 0)
            else
              current_score
            end
          end
        end
      end
    end
  end
end
