# Feature System Autoloading

## Overview

Familia's feature system includes an autoloading mechanism that automatically discovers and loads feature-specific extension files when features are included in your classes. This allows you to keep your main model files clean while organizing feature-specific configurations in separate files.

## The Problem It Solves

When you include a feature like `safe_dump` in a Familia class:

```ruby
class User < Familia::Horreum
  feature :safe_dump  # This line should trigger autoloading
end
```

You want to be able to define the safe dump configuration in a separate file:

```ruby
# user/safe_dump_extensions.rb
class User
  safe_dump_fields :name, :email  # Don't dump :password
end
```

But there's a **timing problem**: when should this extension file be loaded?

## Why Standard `included` Hook Doesn't Work

The original approach tried to use the standard `included` hook:

```ruby
module SafeDump
  def self.included(base)
    # Try to autoload here - BUT THIS IS TOO EARLY!
    autoload_files_for(base)
  end
end
```

**Problem**: This happens **during** the feature inclusion process, before the feature is fully set up. The class isn't in a stable state yet.

## The Solution: Post-Inclusion Hook

The `post_inclusion_autoload` system works in **two phases**:

### Feature System Hook

In `lib/familia/features.rb`, after including the feature module:

```ruby
def feature(feature_name, **options)
  # ... setup code ...

  include feature_class  # Include the feature module

  # NOW call the post-inclusion hook
  if feature_class.respond_to?(:post_inclusion_autoload)
    feature_class.post_inclusion_autoload(self, feature_name, options)
  end
end
```

3. **Loads any matching files** found in those locations

## Why This Timing Matters

```ruby
class User < Familia::Horreum
  feature :safe_dump  # ← Timing is critical here
end
```

**What happens in order:**

1. `feature :safe_dump` is called
2. Feature system includes `Familia::Features::SafeDump` module
3. **Feature is now fully included and stable**
4. `post_inclusion_autoload` is called
5. Extension files are discovered and loaded
6. `safe_dump_fields :name, :email` executes in the extension file

## File Naming Conventions

The autoloading system looks for files matching these patterns (in order of precedence):

1. `{model_directory}/{model_name}/{feature_name}_*.rb`
2. `{model_directory}/{model_name}/features/{feature_name}_*.rb`
3. `{model_directory}/features/{feature_name}_*.rb`

### Examples

For a `User` class defined in `app/models/user.rb` with `feature :safe_dump`:

```
app/models/user/safe_dump_extensions.rb     # ← Most specific
app/models/user/safe_dump_config.rb         # ← Also matches pattern
app/models/user/features/safe_dump_*.rb     # ← Feature subdirectory
app/models/features/safe_dump_*.rb          # ← Shared feature configs
```

## Complete Example

### Main Model File

```ruby
# app/models/user.rb
class User < Familia::Horreum
  field :name
  field :email
  field :password
  field :created_at

  feature :safe_dump  # ← Triggers autoloading
  feature :expiration
end
```

### Safe Dump Extensions

```ruby
# app/models/user/safe_dump_extensions.rb
class User
  # Configure which fields are safe to dump in API responses
  safe_dump_fields :name, :email, :created_at
  # Note: :password is intentionally excluded for security

  def safe_dump_display_name
    "#{name} (#{email})"
  end
end
```

### Expiration Extensions

```ruby
# app/models/user/expiration_config.rb
class User
  # Set default TTL for user objects
  expires_in 30.days

  # Custom expiration logic
  def should_expire?
    !active? && last_login_at < 90.days.ago
  end
end
```

### Result

After loading, the `User` class has:
- `User.safe_dump_field_names` returns `[:name, :email, :created_at]`
- `User.ttl` returns the configured expiration
- All extension methods are available on instances

## Key Benefits

1. **Separation of Concerns**: Main model file focuses on core definition, extension files handle feature-specific configuration

2. **Convention Over Configuration**: No manual requires, just follow naming conventions

3. **Safe Timing**: Extension files load after the feature is fully set up

4. **Thread Safe**: No shared state between classes

5. **Discoverable**: Clear file organization makes extensions easy to find

## Why It's Better Than Alternatives

- **Manual requires**: Error-prone, verbose, easy to forget
- **Configuration blocks**: Clutters the main model file
- **Included hook**: Wrong timing, class not stable yet
- **Class_eval strings**: Complex, hard to debug and maintain

The `post_inclusion_autoload` system provides a clean, automatic, and safe way to extend feature behavior without polluting the main class definitions.

## Implementation Details

### Autoloader

Looks for features files in models/features.rb, models/features/, models/model_name/features.rb, models/model_name/features/


### Anonymous Class Handling

The system gracefully handles edge cases:

- **Anonymous classes**: Classes without names (e.g., `Class.new`) are skipped
- **Eval contexts**: Classes defined in `eval` or irb are skipped
- **Missing files**: No errors if extension files don't exist

### Error Handling

- Missing extension files are silently ignored
- Syntax errors in extension files propagate normally
- `NameError` during constant resolution is caught and logged

This robust error handling ensures the autoloading system never breaks your application, even with unusual class definitions or missing files.
