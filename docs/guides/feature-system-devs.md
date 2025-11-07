# Feature System Developer Guide

## Overview

The Familia Feature system provides a simple, modular way to add optional functionality to Familia classes. Features are Ruby modules that get included into classes, extending them with additional methods and capabilities.

## Architecture

### Core Components

#### 1. Feature Registration (`Familia::Base`)

Features are registered using the `add_feature` method:

```ruby
module Familia::Base
  def self.add_feature(klass, feature_name, depends_on: [], field_group: nil)
    @features_available ||= {}

    # Create simple feature definition
    feature_def = FeatureDefinition.new(
      name: feature_name,
      depends_on: depends_on,
      field_group: field_group
    )

    # Track feature definitions and availability
    @feature_definitions ||= {}
    @feature_definitions[feature_name] = feature_def
    features_available[feature_name] = klass
  end
end
```

#### 2. Feature Activation (Horreum Classes)

Features are activated using the `feature` method:

```ruby
class MyModel < Familia::Horreum
  feature :expiration
  feature :encrypted_fields
  feature :safe_dump
end
```

#### 3. Feature Definition Structure

Features are defined using a simple Data class:

```ruby
FeatureDefinition = Data.define(:name, :depends_on, :field_group)
```

### Feature Loading Lifecycle

#### 1. Feature Self-Registration

Each feature module registers itself:

```ruby
module Familia::Features::MyFeature
  def self.included(base)
    base.extend ClassMethods
    base.include InstanceMethods
  end

  module ClassMethods
    def my_feature_config
      # Class-level functionality
    end
  end

  module InstanceMethods
    def my_feature_method
      # Instance-level functionality
    end
  end

  # Self-register with the feature system
  Familia::Base.add_feature self, :my_feature, depends_on: []
end
```

#### 2. Runtime Inclusion

When `feature` is called, the system:

1. Validates the feature exists
2. Checks dependencies are satisfied
3. Includes the feature module into the class
4. Stores feature options if provided

```ruby
def feature(feature_name = nil, **options)
  @features_enabled ||= []

  return features_enabled if feature_name.nil?

  feature_name = feature_name.to_sym
  feature_module = Familia::Base.find_feature(feature_name, self)
  raise Familia::Problem, "Unsupported feature: #{feature_name}" unless feature_module

  # Check dependencies
  feature_def = Familia::Base.feature_definitions[feature_name]
  if feature_def&.depends_on&.any?
    missing = feature_def.depends_on - features_enabled
    if missing.any?
      raise Familia::Problem,
            "Feature #{feature_name} requires missing dependencies: #{missing.join(', ')}"
    end
  end

  features_enabled << feature_name
  include feature_module
end
```

## Basic Feature Development

### 1. Feature Structure Template

```ruby
module Familia
  module Features
    module MyFeature
      def self.included(base)
        base.extend ClassMethods
        base.include InstanceMethods
      end

      module ClassMethods
        def my_feature_config
          @my_feature_config ||= {}
        end

        def configure_my_feature(**options)
          my_feature_config.merge!(options)
        end

        def my_feature_enabled?
          features_enabled.include?(:my_feature)
        end
      end

      module InstanceMethods
        def save
          before_my_feature_save if respond_to?(:before_my_feature_save, true)
          result = super
          after_my_feature_save if respond_to?(:after_my_feature_save, true)
          result
        end

        private

        def before_my_feature_save
          # Pre-save logic
        end

        def after_my_feature_save
          # Post-save logic
        end
      end

      # Register the feature
      Familia::Base.add_feature self, :my_feature
    end
  end
end
```

### 2. Feature with Dependencies

```ruby
module Familia::Features::AdvancedFeature
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def advanced_method
      # This feature requires :basic_feature to be enabled
      raise "Basic feature required" unless features_enabled.include?(:basic_feature)
      # Advanced functionality here
    end
  end

  # Register with dependency
  Familia::Base.add_feature self, :advanced_feature, depends_on: [:basic_feature]
end
```

### 3. Feature with Field Groups

```ruby
module Familia::Features::FieldGroupFeature
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def special_field(name, **options)
      # Define fields that belong to this feature
      field(name, **options)
    end
  end

  # Register with field group
  Familia::Base.add_feature self, :field_group_feature, field_group: :special_fields
end
```

## Feature Development Best Practices

### 1. Naming Conventions

- Feature names should be symbols (`:my_feature`)
- Module names should match: `Familia::Features::MyFeature`
- Method names should be prefixed with feature name to avoid conflicts

### 2. Error Handling

```ruby
module Familia::Features::RobustFeature
  class FeatureError < StandardError; end

  def self.included(base)
    validate_environment!
    base.extend ClassMethods
  end

  def self.validate_environment!
    raise FeatureError, "Ruby 3.0+ required" if RUBY_VERSION < "3.0"
  end

  module ClassMethods
    def robust_feature_method
      raise FeatureError, "Feature not properly configured" unless configured?
      # Feature logic here
    end

    private

    def configured?
      # Check if feature is properly set up
      true
    end
  end

  Familia::Base.add_feature self, :robust_feature
end
```

### 3. Feature Options

Features can accept configuration options:

```ruby
class MyModel < Familia::Horreum
  feature :my_feature, timeout: 30, retries: 3
end

# Access options in the feature
module Familia::Features::MyFeature
  module ClassMethods
    def my_feature_timeout
      feature_options(:my_feature)[:timeout] || 60
    end
  end
end
```

## Testing Features

### Feature Testing Helpers

```ruby
module FeatureTestHelpers
  def with_feature(klass, feature_name, **options)
    original_features = klass.features_enabled.dup

    begin
      klass.feature(feature_name, **options)
      yield
    ensure
      # Reset features (note: this is simplified - actual reset is more complex)
      klass.instance_variable_set(:@features_enabled, original_features)
    end
  end

  def feature_enabled?(klass, feature_name)
    klass.features_enabled.include?(feature_name)
  end
end

# Test example
describe Familia::Features::MyFeature do
  include FeatureTestHelpers

  it "adds expected methods to class" do
    with_feature(MyModel, :my_feature) do
      expect(MyModel).to respond_to(:my_feature_config)
      expect(MyModel.new).to respond_to(:my_feature_method)
    end
  end

  it "validates dependencies" do
    expect {
      MyModel.feature(:advanced_feature) # requires :basic_feature
    }.to raise_error(Familia::Problem, /requires missing dependencies/)
  end
end
```

## Existing Features Overview

### Core Features

- **`:expiration`** - TTL management for objects and fields
- **`:encrypted_fields`** - Encrypt sensitive fields before storage
- **`:safe_dump`** - API-safe serialization excluding sensitive fields
- **`:relationships`** - Object associations and indexing
- **`:transient_fields`** - Runtime-only fields that aren't persisted
- **`:quantization`** - Score quantization for sorted sets
- **`:object_identifier`** - Flexible object identification strategies
- **`:external_identifier`** - External system ID management

### Feature Dependencies

Most features are independent, but some have dependencies:

```ruby
# relationships feature has no dependencies
Familia::Base.add_feature Relationships, :relationships

# No complex dependency chains in current implementation
```

## Debugging Features

### Feature Introspection

```ruby
# Check what features are available
Familia::Base.features_available.keys
# => [:expiration, :encrypted_fields, :safe_dump, :relationships, ...]

# Check what features are enabled on a class
MyModel.features_enabled
# => [:expiration, :safe_dump]

# Check feature definitions
Familia::Base.feature_definitions[:expiration]
# => #<data FeatureDefinition name=:expiration, depends_on=[], field_group=nil>

# Check if a specific feature is enabled
MyModel.features_enabled.include?(:expiration)
# => true
```

### Common Issues

1. **Feature not found**: Ensure the feature module is loaded and registered
2. **Dependency errors**: Check that required features are enabled first
3. **Method conflicts**: Features that define the same methods will override each other

## Migration Notes

The feature system is intentionally simple in the current implementation. More complex features like conflict resolution, versioning, and capability flags are not currently implemented but could be added in future versions if needed.

For now, feature developers should:
- Keep features focused and independent
- Use clear naming to avoid method conflicts
- Test features thoroughly in isolation
- Document any dependencies clearly
