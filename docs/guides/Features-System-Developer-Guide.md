# Features System Developer Guide

## Overview

This developer guide covers the internal architecture of Familia's feature system, including feature registration, dependency resolution, loading mechanisms, and best practices for creating robust, maintainable features.

## Architecture Deep Dive

### Core Components

#### 1. Feature Registration (`Familia::Base`)

```ruby
# lib/familia/base.rb
module Familia::Base
  @features_available = {}     # Registry of available features
  @feature_definitions = {}    # Feature metadata and dependencies

  def self.add_feature(klass, feature_name, depends_on: [])
    @features_available ||= {}

    # Create feature definition with metadata
    feature_def = FeatureDefinition.new(
      name: feature_name,
      depends_on: depends_on,
    )

    @feature_definitions ||= {}
    @feature_definitions[feature_name] = feature_def
    features_available[feature_name] = klass
  end
end
```

#### 2. Feature Activation (Horreum Classes)

```ruby
# When a class declares `feature :name`
module Familia::Horreum::ClassMethods
  def feature(name)
    # 1. Validate feature exists
    feature_klass = Familia::Base.features_available[name]
    raise Familia::Problem, "Unknown feature: #{name}" unless feature_klass

    # 2. Check dependencies
    validate_feature_dependencies(name)

    # 3. Include the feature module
    include feature_klass

    # 4. Track enabled features
    @features_enabled ||= Set.new
    @features_enabled.add(name)
  end

  private

  def validate_feature_dependencies(feature_name)
    feature_def = Familia::Base.feature_definitions[feature_name]
    return unless feature_def&.depends_on&.any?

    missing_deps = feature_def.depends_on - features_enabled.to_a
    if missing_deps.any?
      raise Familia::Problem,
        "Feature #{feature_name} requires: #{missing_deps.join(', ')}"
    end
  end
end
```

#### 3. Feature Definition Structure

```ruby
class FeatureDefinition
  attr_reader :name, :depends_on, :conflicts_with, :provides

  def initialize(name:, depends_on: [], conflicts_with: [], provides: [])
    @name = name.to_sym
    @depends_on = Array(depends_on).map(&:to_sym)
    @conflicts_with = Array(conflicts_with).map(&:to_sym)
    @provides = Array(provides).map(&:to_sym)
  end

  def compatible_with?(other_feature)
    !conflicts_with.include?(other_feature.name)
  end

  def dependencies_satisfied?(enabled_features)
    depends_on.all? { |dep| enabled_features.include?(dep) }
  end
end
```

### Feature Loading Lifecycle

#### 1. Automatic Discovery

```ruby
# lib/familia/features.rb - loads all features automatically
features_dir = File.join(__dir__, 'features')
Dir.glob(File.join(features_dir, '*.rb')).sort.each do |feature_file|
  begin
    require_relative feature_file
  rescue LoadError => e
    Familia.logger.warn "Failed to load feature #{feature_file}: #{e.message}"
  end
end
```

#### 2. Feature Self-Registration

```ruby
# Each feature registers itself when loaded
module Familia::Features::MyFeature
  def self.included(base)
    base.extend ClassMethods
    base.prepend InstanceMethods
  end

  module ClassMethods
    # Class-level functionality
  end

  module InstanceMethods
    # Instance-level functionality
  end

  # Self-registration at module definition time
  Familia::Base.add_feature self, :my_feature, depends_on: [:other_feature]
end
```

#### 3. Runtime Inclusion

```ruby
# When a class declares a feature
class MyModel < Familia::Horreum
  feature :expiration      # 1. Validation and dependency check
  feature :encrypted_fields # 2. Module inclusion
  feature :safe_dump        # 3. Method definition and setup
end
```

## Advanced Feature Patterns

### Conditional Feature Loading

```ruby
module Familia::Features::ConditionalFeature
  def self.included(base)
    # Only add functionality if conditions are met
    if defined?(Rails) && Rails.env.production?
      base.extend ProductionMethods
    else
      base.extend DevelopmentMethods
    end

    # Conditional method definitions based on available libraries
    if defined?(Sidekiq)
      base.include BackgroundJobIntegration
    end

    if defined?(ActiveRecord)
      base.include ActiveRecordCompatibility
    end
  end

  module ProductionMethods
    def production_only_method
      # Implementation only available in production
    end
  end

  module DevelopmentMethods
    def debug_helper_method
      # Development and test helper methods
    end
  end

  # Register with environment-specific dependencies
  dependencies = []
  dependencies << :logging if defined?(Rails)
  dependencies << :metrics if ENV['ENABLE_METRICS']

  Familia::Base.add_feature self, :conditional_feature, depends_on: dependencies
end
```

### Feature Conflicts and Compatibility

```ruby
# Feature that conflicts with others
module Familia::Features::AlternativeImplementation
  def self.included(base)
    # Check for conflicting features
    conflicting_features = [:original_implementation, :legacy_mode]
    enabled_conflicts = conflicting_features & base.features_enabled.to_a

    if enabled_conflicts.any?
      raise Familia::Problem,
        "#{self} conflicts with: #{enabled_conflicts.join(', ')}"
    end

    base.extend ClassMethods
  end

  module ClassMethods
    def alternative_method
      # Different implementation approach
    end
  end

  Familia::Base.add_feature self, :alternative_implementation,
    conflicts_with: [:original_implementation, :legacy_mode]
end
```

### Feature Capability Flags

```ruby
module Familia::Features::CapabilityProvider
  def self.included(base)
    base.extend ClassMethods

    # Add capability flags to the class
    base.instance_variable_set(:@capabilities, Set.new)
    base.capabilities.merge([:search, :indexing, :full_text])
  end

  module ClassMethods
    attr_reader :capabilities

    def has_capability?(capability)
      capabilities.include?(capability.to_sym)
    end

    def requires_capability(capability)
      unless has_capability?(capability)
        raise Familia::Problem,
          "#{self} requires #{capability} capability"
      end
    end
  end

  # Feature provides capabilities that other features can depend on
  Familia::Base.add_feature self, :capability_provider, provides: [:search, :indexing]
end

# Feature that requires specific capabilities
module Familia::Features::SearchDependent
  def self.included(base)
    # Check that required capabilities are available
    base.requires_capability(:search)
    base.requires_capability(:indexing)

    base.extend ClassMethods
  end

  module ClassMethods
    def search_by_field(field, query)
      # Implementation that uses search capabilities
    end
  end

  Familia::Base.add_feature self, :search_dependent,
    depends_on: [:capability_provider]
end
```

### Dynamic Feature Configuration

```ruby
module Familia::Features::ConfigurableFeature
  def self.included(base)
    base.extend ClassMethods

    # Initialize configuration
    config = base.feature_config(:configurable_feature)

    if config[:enable_caching]
      base.include CachingMethods
    end

    if config[:enable_logging]
      base.include LoggingMethods
    end

    # Configure behavior based on settings
    base.instance_variable_set(:@batch_size, config[:batch_size] || 100)
  end

  module ClassMethods
    def feature_config(feature_name)
      @feature_configs ||= {}
      @feature_configs[feature_name] ||= load_feature_config(feature_name)
    end

    private

    def load_feature_config(feature_name)
      # Load from various sources
      config = {}

      # 1. Default configuration
      config.merge!(default_config_for(feature_name))

      # 2. Environment variables
      env_config = ENV.select { |k, v| k.start_with?("FAMILIA_#{feature_name.upcase}_") }
      env_config.each { |k, v| config[k.split('_').last.downcase.to_sym] = v }

      # 3. Configuration files
      if defined?(Rails)
        rails_config = Rails.application.config.familia&.features&.dig(feature_name)
        config.merge!(rails_config) if rails_config
      end

      config
    end

    def default_config_for(feature_name)
      case feature_name
      when :configurable_feature
        {
          enable_caching: true,
          enable_logging: Rails.env.development?,
          batch_size: 100,
          timeout: 30
        }
      else
        {}
      end
    end
  end

  module CachingMethods
    def cached_operation(&block)
      # Caching implementation
    end
  end

  module LoggingMethods
    def log_operation(operation, &block)
      # Logging implementation
    end
  end

  Familia::Base.add_feature self, :configurable_feature
end
```

## Feature Development Best Practices

### 1. Feature Structure Template

```ruby
# lib/familia/features/my_feature.rb
module Familia
  module Features
    module MyFeature
      # Feature metadata
      FEATURE_VERSION = '1.0.0'
      REQUIRED_FAMILIA_VERSION = '>= 2.0.0'

      def self.included(base)
        # Validation and setup
        validate_environment!(base)

        Familia.ld "[#{base}] Loading #{self} v#{FEATURE_VERSION}"

        # Module inclusion
        base.extend ClassMethods
        base.prepend InstanceMethods  # Use prepend for method interception
        base.include HelperMethods    # Use include for utility methods

        # Post-inclusion setup
        configure_feature(base)
      end

      def self.validate_environment!(base)
        # Check Familia version compatibility
        familia_version = Gem::Version.new(Familia::VERSION)
        required_version = Gem::Requirement.new(REQUIRED_FAMILIA_VERSION)

        unless required_version.satisfied_by?(familia_version)
          raise Familia::Problem,
            "#{self} requires Familia #{REQUIRED_FAMILIA_VERSION}, " \
            "got #{familia_version}"
        end

        # Check for required methods/capabilities on the base class
        required_methods = [:identifier_field, :field]
        missing_methods = required_methods.reject { |m| base.respond_to?(m) }

        if missing_methods.any?
          raise Familia::Problem,
            "#{base} missing required methods: #{missing_methods.join(', ')}"
        end
      end

      def self.configure_feature(base)
        # Feature-specific initialization
        base.instance_variable_set(:@my_feature_config, {
          enabled: true,
          options: {}
        })

        # Set up feature-specific data structures
        base.class_eval do
          @my_feature_data ||= {}
        end
      end

      # Class-level methods added to including class
      module ClassMethods
        def my_feature_config
          @my_feature_config ||= { enabled: true, options: {} }
        end

        def configure_my_feature(**options)
          my_feature_config[:options].merge!(options)
        end

        def my_feature_enabled?
          my_feature_config[:enabled]
        end
      end

      # Instance methods that intercept/override existing methods
      module InstanceMethods
        def save
          # Pre-processing
          before_my_feature_save if respond_to?(:before_my_feature_save, true)

          # Call original save
          result = super

          # Post-processing
          after_my_feature_save if respond_to?(:after_my_feature_save, true)

          result
        end

        private

        def before_my_feature_save
          # Feature-specific pre-save logic
        end

        def after_my_feature_save
          # Feature-specific post-save logic
        end
      end

      # Utility methods that don't override existing functionality
      module HelperMethods
        def my_feature_helper
          return unless self.class.my_feature_enabled?
          # Helper implementation
        end
      end

      # Register the feature
      Familia::Base.add_feature self, :my_feature, depends_on: [:required_feature]
    end
  end
end
```

### 2. Robust Error Handling

```ruby
module Familia::Features::RobustFeature
  class FeatureError < Familia::Problem; end
  class ConfigurationError < FeatureError; end
  class DependencyError < FeatureError; end

  def self.included(base)
    begin
      validate_dependencies!(base)
      configure_feature_safely(base)
    rescue => e
      handle_inclusion_error(base, e)
    end
  end

  def self.validate_dependencies!(base)
    # Check external dependencies
    unless defined?(SomeGem)
      raise DependencyError, "#{self} requires 'some_gem' gem"
    end

    # Check feature dependencies
    required_features = [:base_feature]
    missing_features = required_features - base.features_enabled.to_a

    if missing_features.any?
      raise DependencyError,
        "#{self} requires features: #{missing_features.join(', ')}"
    end
  end

  def self.configure_feature_safely(base)
    # Safely configure with fallbacks
    config = load_configuration
    apply_configuration(base, config)
  rescue => e
    Familia.logger.warn "Feature configuration failed: #{e.message}"
    apply_default_configuration(base)
  end

  def self.handle_inclusion_error(base, error)
    case error
    when DependencyError
      # Log dependency issues and disable feature
      Familia.logger.error "Feature #{self} disabled: #{error.message}"
      base.instance_variable_set(:@robust_feature_disabled, true)
    when ConfigurationError
      # Try default configuration
      Familia.logger.warn "Using default configuration: #{error.message}"
      apply_default_configuration(base)
    else
      # Re-raise unexpected errors
      raise
    end
  end

  module ClassMethods
    def robust_feature_enabled?
      !@robust_feature_disabled
    end

    def with_robust_feature(&block)
      return unless robust_feature_enabled?
      block.call
    rescue => e
      Familia.logger.error "Robust feature operation failed: #{e.message}"
      nil
    end
  end

  Familia::Base.add_feature self, :robust_feature
end
```

### 3. Feature Testing Infrastructure

```ruby
# Test helpers for feature development
module FeatureTestHelpers
  def with_feature(feature_name, config = {})
    # Create temporary test class with feature
    test_class = Class.new(Familia::Horreum) do
      def self.name
        'FeatureTestClass'
      end

      identifier_field :test_id
      field :test_id
    end

    # Configure feature if needed
    if config.any?
      test_class.define_singleton_method(:feature_config) do |name|
        config
      end
    end

    # Enable the feature
    test_class.feature feature_name

    yield test_class
  end

  def feature_enabled?(klass, feature_name)
    klass.features_enabled.include?(feature_name)
  end

  def assert_feature_methods(klass, expected_methods)
    expected_methods.each do |method|
      assert klass.method_defined?(method),
        "Expected #{klass} to have method #{method}"
    end
  end
end

# RSpec helper
RSpec.configure do |config|
  config.include FeatureTestHelpers
end

# Feature test example
RSpec.describe Familia::Features::MyFeature do
  it "adds expected methods to class" do
    with_feature(:my_feature) do |test_class|
      expect(test_class).to respond_to(:my_feature_config)
      expect(test_class.new).to respond_to(:my_feature_helper)
    end
  end

  it "respects feature configuration" do
    config = { enabled: false }

    with_feature(:my_feature, config) do |test_class|
      expect(test_class.my_feature_enabled?).to be false
    end
  end

  it "validates dependencies" do
    expect {
      Class.new(Familia::Horreum) do
        feature :my_feature  # Missing :required_feature dependency
      end
    }.to raise_error(Familia::Problem, /requires.*required_feature/)
  end
end
```

## Performance Optimization

### 1. Lazy Feature Loading

```ruby
module Familia::Features::LazyFeature
  def self.included(base)
    # Minimal setup at include time
    base.extend ClassMethods

    # Defer expensive setup until first use
    @setup_complete = false
  end

  module ClassMethods
    def ensure_lazy_feature_setup!
      return if @setup_complete

      # Expensive setup operations
      perform_expensive_setup
      @setup_complete = true
    end

    def lazy_feature_method
      ensure_lazy_feature_setup!
      # Method implementation
    end

    private

    def perform_expensive_setup
      # Heavy initialization work
      @expensive_data = load_expensive_data
      @compiled_templates = compile_templates
    end
  end

  Familia::Base.add_feature self, :lazy_feature
end
```

### 2. Feature Method Caching

```ruby
module Familia::Features::CachedFeature
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def cached_feature_method(key)
      @method_cache ||= {}
      @method_cache[key] ||= expensive_computation(key)
    end

    def clear_feature_cache!
      @method_cache = {}
    end

    private

    def expensive_computation(key)
      # Expensive operation
      sleep 0.1  # Simulate work
      "computed_#{key}"
    end
  end

  Familia::Base.add_feature self, :cached_feature
end
```

## Debugging Features

### 1. Feature Introspection

```ruby
module Familia::Features::Introspection
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def feature_info
      {
        enabled_features: features_enabled.to_a,
        feature_dependencies: feature_dependency_graph,
        feature_conflicts: feature_conflict_map,
        feature_load_order: feature_load_order
      }
    end

    def feature_dependency_graph
      graph = {}
      features_enabled.each do |feature|
        definition = Familia::Base.feature_definitions[feature]
        graph[feature] = definition&.depends_on || []
      end
      graph
    end

    def feature_conflict_map
      conflicts = {}
      features_enabled.each do |feature|
        definition = Familia::Base.feature_definitions[feature]
        conflicts[feature] = definition&.conflicts_with || []
      end
      conflicts
    end

    def feature_load_order
      # Return the order features were loaded
      @feature_load_order ||= []
    end

    def debug_feature_issues
      issues = []

      # Check for circular dependencies
      issues.concat(detect_circular_dependencies)

      # Check for method conflicts
      issues.concat(detect_method_conflicts)

      # Check for missing dependencies
      issues.concat(detect_missing_dependencies)

      issues
    end

    private

    def detect_circular_dependencies
      # Implementation for circular dependency detection
    end

    def detect_method_conflicts
      # Implementation for method conflict detection
    end

    def detect_missing_dependencies
      # Implementation for missing dependency detection
    end
  end

  Familia::Base.add_feature self, :introspection
end
```

### 2. Feature Debug Logging

```ruby
module Familia::Features::DebugLogging
  def self.included(base)
    return unless Familia.debug?

    base.extend ClassMethods
    original_feature_method = base.method(:feature)

    base.define_singleton_method(:feature) do |name|
      Familia.ld "[DEBUG] Loading feature #{name} on #{self}"
      start_time = Time.now

      result = original_feature_method.call(name)

      load_time = (Time.now - start_time) * 1000
      Familia.ld "[DEBUG] Feature #{name} loaded in #{load_time.round(2)}ms"

      result
    end
  end

  module ClassMethods
    def log_feature_method_call(method_name, &block)
      return block.call unless Familia.debug?

      Familia.ld "[DEBUG] Calling #{method_name} on #{self}"
      start_time = Time.now

      result = block.call

      duration = (Time.now - start_time) * 1000
      Familia.ld "[DEBUG] #{method_name} completed in #{duration.round(2)}ms"

      result
    end
  end

  Familia::Base.add_feature self, :debug_logging
end
```

## Migration and Versioning

### Feature Versioning

```ruby
module Familia::Features::VersionedFeature
  VERSION = '2.1.0'
  MIGRATION_PATH = [
    { from: '1.0.0', to: '1.1.0', migration: :migrate_1_0_to_1_1 },
    { from: '1.1.0', to: '2.0.0', migration: :migrate_1_1_to_2_0 },
    { from: '2.0.0', to: '2.1.0', migration: :migrate_2_0_to_2_1 }
  ].freeze

  def self.included(base)
    check_and_migrate_version(base)
    base.extend ClassMethods
  end

  def self.check_and_migrate_version(base)
    current_version = get_current_version(base)
    return if current_version == VERSION

    if current_version.nil?
      # First installation
      set_version(base, VERSION)
      return
    end

    # Perform migration
    migrate_from_version(base, current_version, VERSION)
  end

  def self.migrate_from_version(base, from_version, to_version)
    migration_steps = find_migration_path(from_version, to_version)

    migration_steps.each do |step|
      Familia.logger.info "Migrating #{base} from #{step[:from]} to #{step[:to]}"
      send(step[:migration], base)
    end

    set_version(base, to_version)
  end

  def self.find_migration_path(from, to)
    # Find path through migration steps
    current = from
    path = []

    while current != to
      step = MIGRATION_PATH.find { |s| s[:from] == current }
      break unless step

      path << step
      current = step[:to]
    end

    path
  end

  # Migration methods
  def self.migrate_1_0_to_1_1(base)
    # Migration logic for 1.0 -> 1.1
  end

  def self.migrate_1_1_to_2_0(base)
    # Migration logic for 1.1 -> 2.0
  end

  def self.migrate_2_0_to_2_1(base)
    # Migration logic for 2.0 -> 2.1
  end

  module ClassMethods
    def feature_version
      self.class.instance_variable_get(:@versioned_feature_version) || VERSION
    end
  end

  Familia::Base.add_feature self, :versioned_feature
end
```

This developer guide provides the foundation for creating robust, maintainable features that integrate seamlessly with Familia's architecture while following best practices for error handling, performance, and maintainability.
