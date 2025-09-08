# lib/familia/features.rb

# Load the Autoloader first, then use it to load all other features
require_relative 'autoloader'

module Familia
  FeatureDefinition = Data.define(:name, :depends_on)

  # Familia::Features
  #
  # This module provides the feature system for Familia classes. Features are
  # modular capabilities that can be mixed into classes with configurable options.
  # Features provide a powerful way to:
  #
  # - **Add new methods**: Both class and instance methods can be added
  # - **Override existing methods**: Extend or replace default behavior
  # - **Add new fields**: Define additional data storage capabilities
  # - **Manage complexity**: Large, complex model classes can use features to
  #   organize functionality into focused, reusable modules
  #
  # ## Feature Options Storage
  #
  # Feature options are stored **per-class** using class-level instance variables.
  # This means each Familia::Horreum subclass maintains its own isolated set of
  # feature options. When you enable a feature with options in different models,
  # each model stores its own separate configuration without interference.
  #
  # ## Project Organization with Autoloadable
  #
  # For large projects, use {Familia::Features::Autoloadable} to automatically load
  # project-specific features from a dedicated directory structure. This helps
  # organize complex models by separating features into individual files.
  #
  # @example Different models with different feature options
  #   class UserModel < Familia::Horreum
  #     feature :object_identifier, generator: :uuid_v4
  #   end
  #
  #   class SessionModel < Familia::Horreum
  #     feature :object_identifier, generator: :hex
  #   end
  #
  #   UserModel.feature_options(:object_identifier)    #=> {generator: :uuid_v4}
  #   SessionModel.feature_options(:object_identifier) #=> {generator: :hex}
  #
  # @example Using features for complexity management
  #   class ComplexModel < Familia::Horreum
  #     # Organize functionality using features
  #     feature :expiration           # TTL management
  #     feature :safe_dump           # API-safe serialization
  #     feature :relationships       # CRUD operations for related objects
  #     feature :custom_validation   # Project-specific validation logic
  #     feature :audit_trail         # Change tracking
  #   end
  #
  # @example Project-specific features with autoloader
  #   # In your model file: app/models/customer.rb
  #   class Customer < Familia::Horreum
  #     module Features
  #       include Familia::Features::Autoloadable
  #       # Automatically loads all .rb files from app/models/customer/features/
  #     end
  #   end
  #
  # @see Familia::Features::Autoloadable For automatic feature loading
  #
  module Features
    include Familia::Autoloader

    @features_enabled = nil
    attr_reader :features_enabled

    # Enables a feature for the current class with optional configuration.
    #
    # Features are modular capabilities that can be mixed into Familia::Horreum
    # classes. Each feature can be configured with options that are stored
    # **per-class**, ensuring complete isolation between different models.
    #
    # @param feature_name [Symbol, String, nil] the name of the feature to enable.
    #   If nil, returns the list of currently enabled features.
    # @param options [Hash] configuration options for the feature. These are
    #   stored per-class and do not interfere with other models' configurations.
    # @return [Array, nil] the list of enabled features if feature_name is nil,
    #   otherwise nil
    #
    # @example Enable feature without options
    #   class User < Familia::Horreum
    #     feature :expiration
    #   end
    #
    # @example Enable feature with options (per-class storage)
    #   class User < Familia::Horreum
    #     feature :object_identifier, generator: :uuid_v4
    #   end
    #
    #   class Session < Familia::Horreum
    #     feature :object_identifier, generator: :hex  # Different options
    #   end
    #
    #   # Each class maintains separate options:
    #   User.feature_options(:object_identifier)    #=> {generator: :uuid_v4}
    #   Session.feature_options(:object_identifier) #=> {generator: :hex}
    #
    # @raise [Familia::Problem] if the feature is not supported
    #
    def feature(feature_name = nil, **options)
      @features_enabled ||= []

      return features_enabled if feature_name.nil?

      # If there's a value provided check that it's a valid feature
      feature_name = feature_name.to_sym
      feature_class = find_feature_module(feature_name)
      unless feature_class
        raise Familia::Problem, "Unsupported feature: #{feature_class}"
      end

      # If the feature is already available, do nothing but log about it
      if features_enabled.member?(feature_name)
        Familia.warn "[#{self.class}] feature already available: #{feature_name}"
        return
      end

      Familia.trace :FEATURE, nil, "#{self} includes #{feature_name.inspect}", caller(1..1) if Familia.debug?

      # Check dependencies and raise error if missing
      feature_def = feature_class.const_get(:FEATURE_DEFINITION) if feature_class.const_defined?(:FEATURE_DEFINITION)
      if feature_def&.depends_on&.any?
        missing = feature_def.depends_on - features_enabled
        if missing.any?
          raise Familia::Problem,
                "Feature #{feature_name} requires missing dependencies: #{missing.join(', ')}"
        end
      end

      # Add it to the list available features_enabled for Familia::Base classes.
      features_enabled << feature_name

      # Always capture and store the calling location for every feature
      calling_location = caller_locations(1, 1)&.first
      options[:calling_location] = calling_location&.path

      # Add feature options if the class supports them (Horreum classes)
      if respond_to?(:add_feature_options)
        add_feature_options(feature_name, **options)
      end

      # Extend the Familia::Base subclass (e.g. Customer) with the feature module
      include feature_class

      # Trigger post-inclusion autoloading for features that support it
      if feature_class.respond_to?(:post_inclusion_autoload)
        feature_class.post_inclusion_autoload(self, feature_name, options)
      end

      # NOTE: Do we want to extend Familia::DataType here? That would make it
      # possible to call safe_dump on relations fields (e.g. list, zset, hashkey).
      #
      # The challenge is that DataType classes (List, Set, etc.) are shared across
      # all Horreum models. If Customer extends DataType with safe_dump, then
      # Session's lists would also have it. Not ideal. If that's all we wanted
      # then we can do that by looping through every DataType class here.
      #
      # We'd need to extend the DataType instances for each Horreum subclass. That
      # avoids it getting included multiple times per DataType
    end

    private

    # Find a feature module using namespace-based resolution.
    #
    # This method looks for feature modules in the following order:
    # 1. Model-specific feature: ModelClass::Features::FeatureName
    # 2. Built-in feature: Familia::Features::FeatureName
    #
    # @param feature_name [Symbol] the snake_case name of the feature
    # @return [Module, nil] the feature module or nil if not found
    #
    def find_feature_module(feature_name)
      # Convert snake_case to CamelCase (e.g., safe_dump -> SafeDump)
      const_name = feature_name.to_s.split('_').map(&:capitalize).join

      Familia.trace :FEATURE, nil, "Looking for feature #{feature_name} as #{const_name}", caller(1..1) if Familia.debug?

      # First, try to find a model-specific feature
      # e.g., Customer::Features::SafeDump
      if self.class.name && self.class.const_defined?(:Features, false)
        features_module = self.class.const_get(:Features)
        if features_module.const_defined?(const_name, false)
          feature_class = features_module.const_get(const_name)
          Familia.trace :FEATURE, nil, "Found model-specific feature: #{feature_class}", caller(1..1) if Familia.debug?
          return feature_class
        end
      end

      # Fallback to built-in features
      # e.g., Familia::Features::SafeDump
      if Familia::Features.const_defined?(const_name, false)
        feature_class = Familia::Features.const_get(const_name)
        Familia.trace :FEATURE, nil, "Found built-in feature: #{feature_class}", caller(1..1) if Familia.debug?
        return feature_class
      end

      Familia.trace :FEATURE, nil, "Feature not found: #{feature_name} (#{const_name})", caller(1..1) if Familia.debug?
      nil
    end
  end
end
